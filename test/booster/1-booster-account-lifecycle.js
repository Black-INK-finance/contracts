const logger = require('mocha-logger');
const BigNumber = require('bignumber.js');
const {
    deployUser,
    setupTokenRoot,
    logContract,
    setupFabric,
    setupDex,
    deployDexPair,
    expect,
    DEX_CONTRACTS_PATH,
    Token,
    sleep,
    MetricManager
} = require("../utils");


describe('Test booster lifecycle', async function() {
    this.timeout(3000000000000);

    let metricManager;

    // Super owner
    let god;

    // Boosters keeper
    let manager;

    // Booster rewards receiver
    let rewarder;

    // Tokens
    let USDT, USDC, BRIDGE, QUBE, LP;
    const god_supply = new BigNumber(1_000_000_000).pow(2);

    // Dex
    let dex_token_factory, dex_root, dex_vault;
    // - Key dex pair, used for farming
    let dex_pair_USDT_USDC;
    // - Pairs for swapping reward to left / right
    let dex_pair_QUBE_USDC;
    let dex_pair_BRIDGE_USDT;

    // - Same initial supply for all pairs
    const dex_pair_initial_supply = new BigNumber(10_000_000_000_000);

    // Farming
    let farming_factory, farming_pool;
    const farmStart = Math.floor(Date.now() / 1000);
    const farming_lifetime = 10000;
    const farmEnd = Math.floor(Date.now() / 1000) + farming_lifetime;
    const farming_reward_per_second_QUBE = new BigNumber(1_000_000_000); // 1
    const farming_reward_per_second_BRIDGE = new BigNumber(2_000_000_000); // 1

    // Booster
    let alice, alice_dex_account, alice_booster_account, alice_booster_account_user_data;
    let booster_factory;

    afterEach(async function() {
        if (metricManager === undefined) return;

        const lastCheckPoint = metricManager.lastCheckPointName();
        const currentName = this.currentTest.title;

        await metricManager.checkPoint(currentName);

        if (lastCheckPoint === undefined) return;

        const difference = await metricManager.getDifference(lastCheckPoint, currentName);

        for (const [contract, balanceDiff] of Object.entries(difference)) {
            if (balanceDiff !== 0) {
                logger.log(`[Balance change] ${contract} ${locklift.utils.convertCrystal(balanceDiff, 'ton').toFixed(9)} EVER`);
            }
        }
    });

    it('Setup actors', async () => {
        god = await deployUser('God');
        alice = await deployUser('Alice');
        rewarder = await deployUser('Rewarder');

        const [keyPair] = await locklift.keys.getKeyPairs();

        const BoosterManager = await locklift.factory.getContract('BoosterManager');
        manager = await locklift.giver.deployContract({
            contract: BoosterManager,
            constructorParams: {
                _owner: `0x${keyPair.public}`,
                _internalOwner: god.address
            }
        }, locklift.utils.convertCrystal(100, 'nano'));
        manager.name = 'Manager';
        manager.setKeyPair(keyPair);

        await logContract(manager);
    });

    describe('Setup tokens', async () => {
        it('Deploy tokens', async () => {
            USDC = await setupTokenRoot('Circle USDC', 'USDC', god);
            USDT = await setupTokenRoot('Tether', 'USDT', god);
            BRIDGE = await setupTokenRoot('Bridge', 'BRIDGE', god);
            QUBE = await setupTokenRoot('FlatQube', 'QUBE', god);
        });

        it('Mint tokens to God', async () => {
            await USDC.mint(god_supply, god);
            await USDT.mint(god_supply, god);
            await QUBE.mint(god_supply, god);
            await BRIDGE.mint(god_supply, god);
        });
    });

    describe('Setup Dex', async () => {
        it('Deploy token factory, dex root, dex vault', async () => {
            [dex_token_factory, dex_root, dex_vault] = await setupDex(god);
        });

        it('Deploy pairs', async () => {
            [dex_pair_USDT_USDC] = await deployDexPair(god, dex_root, USDT, USDC);
            [dex_pair_QUBE_USDC] = await deployDexPair(god, dex_root, QUBE, USDC);
            [dex_pair_BRIDGE_USDT] = await deployDexPair(god, dex_root, BRIDGE, USDT);
        });

        describe('Supply initial liquidity to pairs (all pairs have 1:1 initial liquidity)', async () => {
            let god_dex_account;

            it('Deploy God DEX account', async () => {
                await god.runTarget({
                    contract: dex_root,
                    method: 'deployAccount',
                    params: {
                        account_owner: god.address,
                        send_gas_to: god.address
                    },
                    value: locklift.utils.convertCrystal(10, 'nano')
                });

                const god_dex_account_address = await dex_root.call({
                    method: 'getExpectedAccountAddress',
                    params: {
                        account_owner: god.address
                    }
                });

                god_dex_account = await locklift.factory.getContract('DexAccount', DEX_CONTRACTS_PATH);
                god_dex_account.setAddress(god_dex_account_address);
                god_dex_account.name = 'God dex account';

                await logContract(god_dex_account);
            });

            it('Enable pairs and supply liquidity by God', async () => {
                for (const pair of [dex_pair_USDT_USDC, dex_pair_BRIDGE_USDT, dex_pair_QUBE_USDC]) {
                    const {
                        left: left_address,
                        right: right_address,
                        lp: lp_address
                    } = await pair.call({ method: 'getTokenRoots' });

                    const left = await Token.from_addr(left_address, god);
                    const right = await Token.from_addr(right_address, god);

                    logger.log(`Enabling ${await left.symbol()}-${await right.symbol()} pair`);

                    await god.runTarget({
                        contract: god_dex_account,
                        method: 'addPair',
                        params: {
                            left_root: left.address,
                            right_root: right.address
                        },
                        value: locklift.utils.convertCrystal(10, 'nano')
                    });

                    const left_wallet = await left.wallet(god);
                    const right_wallet = await right.wallet(god);

                    await left_wallet.transfer(
                        dex_pair_initial_supply,
                        god_dex_account.address
                    );

                    await right_wallet.transfer(
                        dex_pair_initial_supply,
                        god_dex_account.address
                    );

                    await god.runTarget({
                        contract: god_dex_account,
                        method: 'depositLiquidity',
                        params: {
                            call_id: locklift.utils.getRandomNonce(),
                            left_root: left.address,
                            left_amount: dex_pair_initial_supply,
                            right_root: right.address,
                            right_amount: dex_pair_initial_supply,
                            expected_lp_root: lp_address,
                            auto_change: true,
                            send_gas_to: god.address
                        },
                        value: locklift.utils.convertCrystal(5, 'nano')
                    });
                }

                await sleep(1000);
            });

            it('Check pair reserves', async () => {
                for (const pair of [dex_pair_USDT_USDC, dex_pair_BRIDGE_USDT, dex_pair_QUBE_USDC]) {
                    const balances = await pair.call({ method: 'getBalances' });

                    expect(balances.left_balance)
                        .to.be.bignumber.equal(dex_pair_initial_supply, `Wrong left balance for ${pair.address}`);
                    expect(balances.right_balance)
                        .to.be.bignumber.equal(dex_pair_initial_supply, `Wrong right balance for ${pair.address}`);
                }
            });
        });
    });

    describe('Setup farming', async () => {
        it('Deploy farming factory', async () => {
            farming_factory = await setupFabric(god, 2, 2, 2);
        });

        it('Deploy farming pool', async () => {
            const lp = await dex_pair_USDT_USDC.call({ method: 'lp_root' });

            logger.log(`Pair LP root: ${lp}`);

            farming_pool = await farming_factory.deployPool({
                pool_owner: god,
                reward_rounds: [
                    {
                        startTime: farmStart,
                        rewardPerSecond: [
                            farming_reward_per_second_QUBE,
                            farming_reward_per_second_BRIDGE
                        ]
                    }
                ],
                tokenRoot: lp,
                rewardTokenRoot: [QUBE.address, BRIDGE.address],
                vestingPeriod: 0,
                vestingRatio: 0,
                withdrawAllLockPeriod: 0
            });
        });

        it('Fill farming pool with QUBE', async () => {
            const wallet = await QUBE.wallet(god);

            await wallet.transfer(
                farming_reward_per_second_QUBE.multipliedBy(farming_lifetime),
                farming_pool.address
            );

            const farming_pool_wallet_QUBE = await QUBE.wallet(farming_pool.address);
            expect(await farming_pool_wallet_QUBE.balance())
                .to.be.bignumber.equal(farming_reward_per_second_QUBE.multipliedBy(farming_lifetime));
        });

        it('Send BRIDGE rewards to farming pool', async () => {
            const wallet = await BRIDGE.wallet(god);

            await wallet.transfer(
                farming_reward_per_second_BRIDGE.multipliedBy(farming_lifetime),
                farming_pool.address
            );

            const farming_pool_wallet_BRIDGE = await BRIDGE.wallet(farming_pool.address);
            expect(await farming_pool_wallet_BRIDGE.balance())
                .to.be.bignumber.equal(farming_reward_per_second_BRIDGE.multipliedBy(farming_lifetime));
        });

        it('Check farming pool received rewards', async () => {
            const details = await farming_pool.details();

            expect(details.rewardTokenBalance[0])
                .to.be.bignumber.equal(
                    farming_reward_per_second_QUBE.multipliedBy(farming_lifetime),
                    'Wrong initial farming QUBE rewards'
                );

            expect(details.rewardTokenBalance[1])
                .to.be.bignumber.equal(
                    farming_reward_per_second_BRIDGE.multipliedBy(farming_lifetime),
                    'Wrong initial farming BRIDGE rewards'
                );
        });

        it('Mint USDT and USDC to Alice', async () => {
            await USDT.mint(dex_pair_initial_supply, alice);
            await USDC.mint(dex_pair_initial_supply, alice);
        });

        it('Alice deposits USDT and USDC to the dex account', async () => {
            await alice.runTarget({
                contract: dex_root,
                method: 'deployAccount',
                params: {
                    account_owner: alice.address,
                    send_gas_to: alice.address
                },
                value: locklift.utils.convertCrystal(10, 'nano')
            });

            const alice_dex_account_address = await dex_root.call({
                method: 'getExpectedAccountAddress',
                params: {
                    account_owner: alice.address
                }
            });

            alice_dex_account = await locklift.factory.getContract('DexAccount', DEX_CONTRACTS_PATH);
            alice_dex_account.setAddress(alice_dex_account_address);
            alice_dex_account.name = 'Alice DEX account';

            await logContract(alice_dex_account);

            await alice.runTarget({
                contract: alice_dex_account,
                method: 'addPair',
                params: {
                    left_root: USDT.address,
                    right_root: USDC.address
                },
                value: locklift.utils.convertCrystal(10, 'nano')
            });

            const alice_wallet_USDT = await USDT.wallet(alice);
            const alice_wallet_USDC = await USDC.wallet(alice);

            await alice_wallet_USDT.transfer(
                dex_pair_initial_supply,
                alice_dex_account.address
            );

            await alice_wallet_USDC.transfer(
                dex_pair_initial_supply,
                alice_dex_account.address
            );

            await sleep(1000);
        });

        it('Check Alice supplied USDT and USDC', async () => {
            const balances = await alice_dex_account.call({ method: 'getBalances' });

            expect(balances[USDT.address])
                .to.be.bignumber.equal(dex_pair_initial_supply, 'Alice failed to deposit USDT');
            expect(balances[USDC.address])
                .to.be.bignumber.equal(dex_pair_initial_supply, 'Alice failed to deposit USDC');
        });

        it('Alice supplies USDT/USDC to the pool', async () => {
            const lp_address = await dex_pair_USDT_USDC.call({ method: 'lp_root' });

            const tx = await alice.runTarget({
                contract: alice_dex_account,
                method: 'depositLiquidity',
                params: {
                    call_id: locklift.utils.getRandomNonce(),
                    left_root: USDT.address,
                    left_amount: dex_pair_initial_supply,
                    right_root: USDC.address,
                    right_amount: dex_pair_initial_supply,
                    expected_lp_root: lp_address,
                    auto_change: true,
                    send_gas_to: alice.address
                },
                value: locklift.utils.convertCrystal(5, 'nano')
            });

            // console.log(tx);

            logger.log(`Alice deposit to USDC/USDT pool tx: ${tx.transaction.id}`);

            LP = await Token.from_addr(lp_address, alice);
            LP.token.name = 'Token root [LP USDT/USDC]';
            const wallet = await LP.wallet(alice);

            expect(await wallet.balance())
                .to.be.bignumber.greaterThan(0, 'Alice failed to receive USDT/USDC LP');
        });
    });

    describe('Setup booster', async () => {
        it('Deploy booster factory', async () => {
            const BoosterFactory = await locklift.factory.getContract('BoosterFactory');
            const BoosterAccountPlatform = await locklift.factory.getContract('BoosterAccountPlatform')
            const BoosterAccount = await locklift.factory.getContract('BoosterAccount');

            booster_factory = await locklift.giver.deployContract({
                contract: BoosterFactory,
                constructorParams: {
                    _owner: god.address,
                    _manager: manager.address,
                    _account_platform: BoosterAccountPlatform.code,
                    _account: BoosterAccount.code
                },
            });

            await logContract(booster_factory);

            const details = await booster_factory.call({ method: 'getDetails' });

            expect(details._version)
                .to.be.bignumber.equal(0, 'Wrong factory version');
            expect(details._account_version)
                .to.be.bignumber.equal(0, 'Wrong factory account version');
            expect(details._manager)
                .to.be.equal(manager.address, 'Wrong factory manager');
        });

        it('Add farming pool to the booster factory', async () => {
            const lp_address = await dex_pair_USDT_USDC.call({ method: 'lp_root' });

            await god.runTarget({
                contract: booster_factory,
                method: 'addFarming',
                params: {
                    dex: dex_root.address,
                    farming_pool: farming_pool.address,
                    lp: lp_address,
                    pair: dex_pair_USDT_USDC.address,
                    left: USDC.address,
                    right: USDT.address,
                    rewards: [BRIDGE.address, QUBE.address],
                    swaps: {
                        [BRIDGE.address]: {
                            token: USDT.address,
                            pair: dex_pair_BRIDGE_USDT.address
                        },
                        [QUBE.address]: {
                            token: USDC.address,
                            pair: dex_pair_QUBE_USDC.address
                        }
                    },
                    recommended_ping_frequency: 20 * 60, // 1 minute
                    rewarder: rewarder.address,
                    fee: 10
                }
            });

            const details = await booster_factory.call({ method: 'getDetails' });

            expect(details._farmings[farming_pool.address].fee)
                .to.be.bignumber.equal(10, 'Wrong fee in farming');
            expect(details._farmings[farming_pool.address].paused)
                .to.be.equal(false, 'Farming should be paused');
            expect(details._farmings[farming_pool.address].rewarder)
                .to.be.equal(rewarder.address, 'Wrong rewarder in farming');
        });

        // it('Unpause farming pool', async () => {
        //     await god.runTarget({
        //         contract: booster_factory,
        //         method: 'setFarmingPaused',
        //         params: {
        //             farming_pool: farming_pool.address,
        //             paused: false
        //         }
        //     });
        //
        //     const details = await booster_factory.call({ method: 'getDetails' });
        //
        //     expect(details._farmings[farming_pool.address].paused)
        //         .to.be.equal(false, 'Farming should be unpaused');
        // });

        it('Deploy Alice booster account', async () => {
            await alice.runTarget({
                contract: booster_factory,
                method: 'deployAccount',
                params: {
                    _owner: alice.address,
                    farming_pool: farming_pool.address,
                    ping_frequency: 60 * 20
                },
                value: locklift.utils.convertCrystal(11, 'nano')
            });

            const alice_booster_account_address = await booster_factory.call({
                method: 'deriveAccount',
                params: {
                    _owner: alice.address,
                    farming_pool: farming_pool.address
                }
            });

            alice_booster_account = await locklift.factory.getContract('BoosterAccount');
            alice_booster_account.setAddress(alice_booster_account_address);
            alice_booster_account.name = 'Alice booster account';

            await logContract(alice_booster_account);
        });

        it('Check Alice booster account initialized', async () => {
            const initialized = await alice_booster_account.call({ method: 'isInitialized' });

            expect(initialized)
                .to.be.equal(true, 'Alice account not initialized');
        });

        it('Check Alice booster account details', async () => {
            const details = await alice_booster_account.call({ method: 'getDetails' });

            expect(details._owner)
                .to.be.equal(alice.address, 'Wrong booster owner');
            expect(details._version)
                .to.be.bignumber.equal(0, 'Wrong booster version');
            expect(details._factory)
                .to.be.equal(booster_factory.address, 'Wrong booster factory');
            expect(details._farming_pool)
                .to.be.equal(farming_pool.address, 'Wrong booster farming pool');
            expect(details._settings.ping_frequency)
                .to.be.bignumber.equal(60 * 20, 'Wrong booster ping frequency');

            logger.log(`Booster USDT wallet: ${details._tokens[USDT.address].wallet}`);
            logger.log(`Booster USDC wallet: ${details._tokens[USDC.address].wallet}`);
            logger.log(`Booster QUBE wallet: ${details._tokens[QUBE.address].wallet}`);
            logger.log(`Booster BRIDGE wallet: ${details._tokens[BRIDGE.address].wallet}`);
            logger.log(`Booster LP wallet: ${details._tokens[LP.address].wallet}`);
        });
    });

    describe('Alice uses booster', async () => {
        it('Alice transfers LP to the booster account', async () => {
            const lp_address = await dex_pair_USDT_USDC.call({ method: 'lp_root' });

            const lp = await Token.from_addr(lp_address, alice);
            const wallet = await lp.wallet(alice);

            const tx = await wallet.transfer(
                (await wallet.balance()),
                alice_booster_account.address
            );

            await sleep(1000);

            logger.log(`Alice first LP deposit to booster tx: ${tx.transaction.id}`);

            const details = await alice_booster_account.call({ method: 'getDetails' });

            expect(details._tokens[lp_address].balance)
                .to.be.bignumber.equal(0, 'Booster LP balance should be zero');
            expect(details._tokens[lp_address].received)
                .to.be.bignumber.greaterThan(0, 'Booster LP received should be positive');
        });

        it('Check Alice booster has position in farming', async () => {
            const events = await farming_pool.getEvents('Deposit');
            const details = await alice_booster_account.call({ method: 'getDetails' });

            expect(events)
                .to.have.lengthOf(1, 'Wrong farming deposits amount');

            const [event] = events;

            const lp_address = await dex_pair_USDT_USDC.call({ method: 'lp_root' });

            expect(event.value.user)
                .to.be.equal(alice_booster_account.address, 'Wrong farming deposit author');
            expect(event.value.amount)
                .to.be.bignumber.equal(details._tokens[lp_address].received, 'Wrong farming deposit amount');

            // Save Alice booster user data
            alice_booster_account_user_data = await locklift.factory.getContract('UserDataV3');
            alice_booster_account_user_data.setAddress(details._user_data);
            alice_booster_account_user_data.name = 'Alice booster user data';

            await logContract(alice_booster_account_user_data);
        });

        describe('First ping', async () => {
            let _details, _position;

            it('Setup metric manager', async () => {
                // Farming token wallets
                const farming_qube = (await QUBE.wallet(farming_pool)).wallet;
                farming_qube.name = 'Farming QUBE wallet';
                const farming_bridge = (await BRIDGE.wallet(farming_pool)).wallet;
                farming_bridge.name = 'Farming BRIDGE wallet';
                const farming_lp = (await LP.wallet(farming_pool)).wallet;
                farming_lp.name = 'Farming LP wallet';

                // Booster token wallets
                const booster_qube = (await QUBE.wallet(alice_booster_account)).wallet;
                booster_qube.name = 'Booster QUBE wallet';
                const booster_bridge = (await BRIDGE.wallet(alice_booster_account)).wallet;
                booster_bridge.name = 'Booster BRIDGE wallet';
                const booster_lp = (await LP.wallet(alice_booster_account)).wallet;
                booster_lp.name = 'Booster LP wallet';
                const booster_usdt = (await LP.wallet(alice_booster_account)).wallet;
                booster_usdt.name = 'Booster USDT wallet';
                const booster_usdc = (await LP.wallet(alice_booster_account)).wallet;
                booster_usdc.name = 'Booster USDC wallet';

                // Dex vault token wallets
                const dex_vault_qube = (await QUBE.wallet(dex_vault)).wallet;
                dex_vault_qube.name = 'DEX Vault QUBE wallet';
                const dex_vault_bridge = (await BRIDGE.wallet(dex_vault)).wallet;
                dex_vault_bridge.name = 'DEX Vault BRIDGE wallet';
                const dex_vault_lp = (await LP.wallet(dex_vault)).wallet;
                dex_vault_lp.name = 'DEX Vault LP wallet';
                const dex_vault_usdt = (await LP.wallet(dex_vault)).wallet;
                dex_vault_usdt.name = 'DEX Vault USDT wallet';
                const dex_vault_usdc = (await LP.wallet(dex_vault)).wallet;
                dex_vault_usdc.name = 'DEX Vault USDC wallet';

                // Dex pairs token wallets
                const dex_pair_QUBE_USDC_qube = (await QUBE.wallet(dex_pair_QUBE_USDC)).wallet;
                dex_pair_QUBE_USDC_qube.name = 'Pair QUBE/USDC QUBE wallet';
                const dex_pair_QUBE_USDC_usdc = (await USDC.wallet(dex_pair_QUBE_USDC)).wallet;
                dex_pair_QUBE_USDC_usdc.name = 'Pair QUBE/USDC USDC wallet';

                const dex_pair_USDT_USDC_usdt = (await USDT.wallet(dex_pair_USDT_USDC)).wallet;
                dex_pair_USDT_USDC_usdt.name = 'Pair USDT/USDC USDT wallet';
                const dex_pair_USDT_USDC_usdc = (await USDC.wallet(dex_pair_USDT_USDC)).wallet;
                dex_pair_USDT_USDC_usdc.name = 'Pair USDT/USDC USDC wallet';

                const dex_pair_BRIDGE_USDT_bridge = (await BRIDGE.wallet(dex_pair_BRIDGE_USDT)).wallet;
                dex_pair_BRIDGE_USDT_bridge.name = 'Pair BRIDGE/USDT BRIDGE wallet';
                const dex_pair_BRIDGE_USDT_usdt = (await USDT.wallet(dex_pair_BRIDGE_USDT)).wallet;
                dex_pair_BRIDGE_USDT_usdt.name = 'Pair BRIDGE/USDT USDT wallet';

                metricManager = new MetricManager(
                    god,
                    alice,
                    manager,
                    rewarder,

                    dex_root,
                    dex_vault,
                    dex_pair_QUBE_USDC,
                    dex_pair_USDT_USDC,
                    dex_pair_BRIDGE_USDT,

                    farming_pool.pool,
                    farming_qube,
                    farming_bridge,
                    farming_lp,

                    booster_qube,
                    booster_bridge,
                    booster_lp,
                    booster_usdt,
                    booster_usdc,

                    dex_vault_qube,
                    dex_vault_bridge,
                    dex_vault_lp,
                    dex_vault_usdt,
                    dex_vault_usdc,

                    dex_pair_QUBE_USDC_qube,
                    dex_pair_QUBE_USDC_usdc,
                    dex_pair_USDT_USDC_usdt,
                    dex_pair_USDT_USDC_usdc,
                    dex_pair_BRIDGE_USDT_bridge,
                    dex_pair_BRIDGE_USDT_usdt,

                    USDC.token,
                    USDT.token,
                    BRIDGE.token,
                    QUBE.token,
                    LP.token,

                    alice_booster_account,
                    alice_booster_account_user_data,
                );
            });

            it('Sleep 10 seconds to achieve farming rewards', async () => {
                await sleep(10 * 1000);
            });

            it('Save metrics before ping', async () => {
                _details = await alice_booster_account.call({ method: 'getDetails' });
                _position = await alice_booster_account_user_data.call({ method: 'getDetails' });
            });

            it('Ping', async () => {
                const tx = await manager.run({
                    method: 'ping',
                    params: {
                        pings: [{
                            account: alice_booster_account.address,
                            skim: false
                        }]
                    }
                });

                logger.success(`First ping tx (reinvest rewards): ${tx.transaction.id}`);

                logger.log('Sleep a little');
                await sleep(5 * 1000);
            });

            // it('Disable metric manager', async () => {
            //     metricManager = undefined;
            // });

            it('Check booster virtual balances', async () => {
                const details = await alice_booster_account.call({ method: 'getDetails' });
                const position = await alice_booster_account_user_data.call({ method: 'getDetails' });

                expect(details._tokens[BRIDGE.address].received)
                    .to.be.bignumber.greaterThan(_details._tokens[BRIDGE.address].received, 'Booster should receive BRIDGE after ping')
                    .to.be.bignumber.greaterThan(0, 'Booster should receive BRIDGE reward');

                expect(details._tokens[QUBE.address].received)
                    .to.be.bignumber.greaterThan(_details._tokens[QUBE.address].received, 'Booster should receive BRIDGE after ping')
                    .to.be.bignumber.greaterThan(0, 'Booster should receive QUBE reward');

                expect(details._tokens[USDT.address].received)
                    .to.be.bignumber.greaterThan(_details._tokens[USDT.address].received, 'Booster should receive USDT after ping')
                    .to.be.bignumber.greaterThan(0, 'Booster should receive USDT after swap');

                expect(details._tokens[USDC.address].received)
                    .to.be.bignumber.greaterThan(_details._tokens[USDC.address].received, 'Booster should receive BRIDGE after ping')
                    .to.be.bignumber.greaterThan(0, 'Booster should receive USDC after swap');

                expect(details._tokens[details._settings.lp].received)
                    .to.be.bignumber.greaterThan(_details._tokens[details._settings.lp].received, 'Booster should receive LP after ping')
                    .to.be.bignumber.greaterThan(0, 'Booster should receive LP')
                    .to.be.bignumber.equal(position.amount, 'Booster should deposit all LP to farming');
            });
        });

        describe('Alice stops using booster', async () => {
            it('Alice pauses booster', async () => {
                await alice.runTarget({
                    contract: alice_booster_account,
                    method: 'setPaused',
                    params: {
                        _paused: true
                    }
                });

                expect(await alice_booster_account.call({ method: 'paused' }))
                    .to.be.equal(true);
            });

            it('Alice withdraws LPs from farming', async () => {
                const lp_to_withdraw = 100;

                const alice_lp_wallet = await LP.wallet(alice);

                expect(await alice_lp_wallet.balance())
                    .to.be.bignumber.equal(0, 'Alice should has no LPs before withdrawing them from booster');

                const {
                    amount: booster_lp_balance_before_withdraw
                } = await alice_booster_account_user_data.call({ method: 'getDetails' });

                const tx = await alice.runTarget({
                    contract: alice_booster_account,
                    method: 'requestFarmingLP',
                    params: {
                        amount: lp_to_withdraw
                    },
                    value: locklift.utils.convertCrystal(5, 'nano')
                });

                logger.log(`Request farming LP from booster tx: ${tx.transaction.id}`);

                const {
                    amount: booster_lp_balance
                } = await alice_booster_account_user_data.call({ method: 'getDetails' });

                expect(await alice_lp_wallet.balance())
                    .to.be.bignumber.equal(lp_to_withdraw, 'Wrong Alice LP balance after LP withdraw');
                expect(booster_lp_balance)
                    .to.be.bignumber.equal(
                        booster_lp_balance_before_withdraw - lp_to_withdraw,
                        'Wrong booster balance after LP withdraw'
                    );
            });

            it('Ping booster to claim rewards and transfer them to the user', async () => {
                const alice_qube = await QUBE.wallet(alice);
                const alice_bridge = await BRIDGE.wallet(alice);

                await sleep(10 * 1000);

                const tx = await manager.run({
                    method: 'ping',
                    params: {
                        pings: [{
                            account: alice_booster_account.address,
                            skim: false
                        }]
                    }
                });

                logger.success(`Second ping tx (claim rewards): ${tx.transaction.id}`);

                await sleep(2 * 1000);

                expect(await alice_qube.balance())
                    .to.be.bignumber.greaterThan(0, 'Alice should receive QUBE reward');
                expect(await alice_bridge.balance())
                    .to.be.bignumber.greaterThan(0, 'Alice should receive BRIDGE reward');
            });
        });

        describe('Claim rewarder fees', async () => {
            let details_before_skim;

            it('Check booster recorded fees', async () => {
                details_before_skim = await alice_booster_account.call({ method: 'getDetails' });

                expect(details_before_skim._tokens[QUBE.address].fee)
                    .to.be.bignumber.greaterThan(0, 'QUBE fees should be non-zero');
                expect(details_before_skim._tokens[BRIDGE.address].fee)
                    .to.be.bignumber.greaterThan(0, 'BRIDGE fees should be non-zero');

                expect(details_before_skim._tokens[USDT.address].fee)
                    .to.be.bignumber.equal(0, 'USDT fees should be zero');
                expect(details_before_skim._tokens[USDC.address].fee)
                    .to.be.bignumber.equal(0, 'USDC fees should be zero');
                expect(details_before_skim._tokens[LP.address].fee)
                    .to.be.bignumber.equal(0, 'LP fees should be zero');
            });

            it('Claim fees', async () => {
                const tx = await manager.run({
                    method: 'ping',
                    params: {
                        pings: [{
                            account: alice_booster_account.address,
                            skim: true
                        }]
                    }
                });

                logger.success(`Third ping tx (claim rewards and skim fees): ${tx.transaction.id}`);
            });

            it('Check fees are zero after skim', async () => {
                const details = await alice_booster_account.call({ method: 'getDetails' });

                expect(details._tokens[QUBE.address].fee)
                    .to.be.bignumber.equal(0, 'QUBE fees should be zero');
                expect(details._tokens[BRIDGE.address].fee)
                    .to.be.bignumber.equal(0, 'BRIDGE fees should be zero');
                expect(details._tokens[USDT.address].fee)
                    .to.be.bignumber.equal(0, 'USDT fees should be zero');
                expect(details._tokens[USDC.address].fee)
                    .to.be.bignumber.equal(0, 'USDC fees should be zero');
                expect(details._tokens[LP.address].fee)
                    .to.be.bignumber.equal(0, 'LP fees should be zero');
            });
        });
    });
});
