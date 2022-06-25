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

    // Manager keys
    let manager1,manager2;

    // Booster rewards receiver
    let rewarder;

    // Tokens
    let USDT, USDC, BRIDGE, QUBE, LP, PING;
    const god_supply = new BigNumber(1_000_000_000).pow(2);
    const alice_ping_initial_balance = 10_000;

    // Dex
    let dex_token_factory, dex_root, dex_vault;
    // - Key dex pair, used for farming
    let dex_pair_USDT_USDC;
    // - Pairs for swapping reward to left / right
    let dex_pair_QUBE_USDC;
    let dex_pair_BRIDGE_USDT;

    // - Same initial supply for all pairs
    const dex_pair_initial_supply = new BigNumber(10_000_000_000_000);

    const max_ping_price = 1000;
    const ping_frequency = 20; // 20 seconds

    // Farming
    let farming_factory, farming_pool;
    const farmStart = Math.floor(Date.now() / 1000);
    const farming_lifetime = 10000;
    const farmEnd = Math.floor(Date.now() / 1000) + farming_lifetime;
    const farming_reward_per_second_QUBE = new BigNumber(1_000_000_000); // 1
    const farming_reward_per_second_BRIDGE = new BigNumber(2_000_000_000); // 1

    // Booster
    let alice, alice_dex_account, alice_booster_account, alice_passport, alice_booster_account_user_data;
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
        // rewarder = await deployUser('Rewarder');
    });

    it('Setup booster manager', async () => {
        [,manager1,manager2] = await locklift.keys.getKeyPairs();
    });

    describe('Setup tokens', async () => {
        it('Deploy tokens', async () => {
            USDC = await setupTokenRoot('Circle USDC', 'USDC', god);
            USDT = await setupTokenRoot('Tether', 'USDT', god);
            BRIDGE = await setupTokenRoot('Octus Bridge', 'BRIDGE', god);
            QUBE = await setupTokenRoot('FlatQube', 'QUBE', god);

            PING = await setupTokenRoot('Ping', 'PING', god);
        });

        it('Mint tokens to God', async () => {
            await USDC.mint(god_supply, god);
            await USDT.mint(god_supply, god);
            await QUBE.mint(god_supply, god);
            await BRIDGE.mint(god_supply, god);
            await PING.mint(god_supply, god);
        });

        it('Transfer PING tokens to Alice', async () => {
            await PING.deployWallet(alice);

            const god_ping = await PING.wallet(god);
            await god_ping.transfer(alice_ping_initial_balance, alice);

            const alice_ping = await PING.wallet(alice);
            expect(await alice_ping.balance())
                .to.be.bignumber.equal(alice_ping_initial_balance, 'Wrong Alice ping initial balance');
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

                await sleep(2000);
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

            it('Setup USDT/USDC LP token', async () => {
                const token_roots = await dex_pair_USDT_USDC.call({
                    method: 'getTokenRoots',
                });

                LP = await Token.from_addr(token_roots.lp, alice);
                LP.token.name = 'Token root [LP USDT/USDC]';
            });
        });
    });

    describe('Setup rewarder (buyback)', async () => {
        it('Deploy booster buyback', async () => {
            const BoosterBuyBack = await locklift.factory.getContract('BoosterBuyBack');

            rewarder = await locklift.giver.deployContract({
                contract: BoosterBuyBack,
                constructorParams: {
                    _owner: god.address
                }
            }, locklift.utils.convertCrystal(100, 'nano'));
            rewarder.name = 'Rewarder (BuyBack)';

            await logContract(rewarder);
        });

        it('Initialize PING and LP tokens without swap rules', async () => {
            await god.runTarget({
                contract: rewarder,
                method: 'initializeTokens',
                params: {
                    tokens: [
                        PING.address,
                        LP.address,
                        QUBE.address,
                        BRIDGE.address,
                        USDT.address,
                        USDC.address
                    ]
                }
            });
        });

        it('Initialize swap rules for QUBE and BRIDGE', async () => {
            await god.runTarget({
                contract: rewarder,
                method: 'setTokenSwap',
                params: {
                    token: BRIDGE.address,
                    swap: {
                        token: USDT.address,
                        pair: dex_pair_BRIDGE_USDT.address,
                        minToSwap: 0
                    },
                }
            });

            await god.runTarget({
                contract: rewarder,
                method: 'setTokenSwap',
                params: {
                    token: QUBE.address,
                    swap: {
                        token: USDC.address,
                        pair: dex_pair_QUBE_USDC.address,
                        minToSwap: 0
                    }
                }
            });
        });

        it('Check rewarder initialized', async () => {

        });
    });

    describe('Setup farming', async () => {
        it('Deploy farming factory', async () => {
            farming_factory = await setupFabric(god, 1, 1, 1);
        });

        it('Deploy farming pool', async () => {
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
                tokenRoot: LP.address,
                rewardTokenRoot: [QUBE.address, BRIDGE.address],
                vestingPeriod: 0,
                vestingRatio: 0,
                withdrawAllLockPeriod: 0
            });

            await logContract(farming_pool.pool);
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
            const tx = await alice.runTarget({
                contract: alice_dex_account,
                method: 'depositLiquidity',
                params: {
                    call_id: locklift.utils.getRandomNonce(),
                    left_root: USDT.address,
                    left_amount: dex_pair_initial_supply,
                    right_root: USDC.address,
                    right_amount: dex_pair_initial_supply,
                    expected_lp_root: LP.address,
                    auto_change: true,
                    send_gas_to: alice.address
                },
                value: locklift.utils.convertCrystal(5, 'nano')
            });

            // console.log(tx);

            logger.success(`Alice deposit to USDC/USDT pool tx: ${tx.transaction.id}`);

            const wallet = await LP.wallet(alice);

            expect(await wallet.balance())
                .to.be.bignumber.greaterThan(0, 'Alice failed to receive USDT/USDC LP');
        });
    });

    describe('Setup booster', async () => {
        it('Deploy booster factory', async () => {
            const BoosterFactory = await locklift.factory.getContract('BoosterFactory');
            const BoosterAccountPlatform = await locklift.factory.getContract('BoosterAccountPlatform')
            const BoosterAccount = await locklift.factory.getContract('BoosterAccount_V1');
            const BoosterPassportPlatform = await locklift.factory.getContract('BoosterPassportPlatform');
            const BoosterPassport = await locklift.factory.getContract('BoosterPassport');

            booster_factory = await locklift.giver.deployContract({
                contract: BoosterFactory,
                constructorParams: {
                    _owner: god.address,
                    _managers: [`0x${manager1.public}`, `0x${manager2.public}`],
                    _rewarder: rewarder.address,
                    _ping_token_root: PING.address,
                    _account_platform: BoosterAccountPlatform.code,
                    _account_implementation: '',
                    _passport_platform: BoosterPassportPlatform.code,
                    _passport_implementation: ''
                },
            }, locklift.utils.convertCrystal(60, 'nano'));

            await logContract(booster_factory);

            await god.runTarget({
                contract: booster_factory,
                method: 'upgradeAccountCode',
                params: {
                    _account_implementation: BoosterAccount.code
                }
            });

            await god.runTarget({
                contract: booster_factory,
                method: 'upgradePassportCode',
                params: {
                    _passport_implementation: BoosterPassport.code
                }
            });

            const details = await booster_factory.call({ method: 'getDetails' });

            expect(details._version)
                .to.be.bignumber.equal(0, 'Wrong factory version');
            expect(details._account_version)
                .to.be.bignumber.equal(1, 'Wrong factory account version');
            expect(details._passport_version)
                .to.be.bignumber.equal(1, 'Wrong factory passport version');
        });

        it('Add farming pool to the booster factory', async () => {
            await god.runTarget({
                contract: booster_factory,
                method: 'addFarming',
                params: {
                    farming_pool: farming_pool.address,
                    vault: dex_vault.address,
                    lp: LP.address,
                    pair: dex_pair_USDT_USDC.address,
                    left: USDC.address,
                    right: USDT.address,
                    rewards: [BRIDGE.address, QUBE.address],
                    swaps: {
                        [BRIDGE.address]: {
                            token: USDT.address,
                            pairType: 0,
                            pair: dex_pair_BRIDGE_USDT.address
                        },
                        [QUBE.address]: {
                            token: USDC.address,
                            pairType: 0,
                            pair: dex_pair_QUBE_USDC.address
                        }
                    },
                    rewarder: rewarder.address,
                    reward_fee: 5,
                    lp_fee: 5,
                    ping_value: locklift.utils.convertCrystal(2.5, 'nano')
                }
            });

            const details = await booster_factory.call({ method: 'getDetails' });

            expect(details._farmings[farming_pool.address].reward_fee)
                .to.be.bignumber.equal(5, 'Wrong reward fee in farming');
            expect(details._farmings[farming_pool.address].lp_fee)
                .to.be.bignumber.equal(5, 'Wrong lp fee in farming');
            expect(details._farmings[farming_pool.address].rewarder)
                .to.be.equal(rewarder.address, 'Wrong rewarder in farming');
        });

        it('Deploy Alice booster account', async () => {
            await alice.runTarget({
                contract: booster_factory,
                method: 'deployAccount',
                params: {
                    farming_pool: farming_pool.address,
                    ping_frequency,
                    max_ping_price,
                    deploy_passport: true
                },
                value: locklift.utils.convertCrystal(50, 'nano')
            });

            const alice_booster_account_address = await booster_factory.call({
                method: 'deriveAccount',
                params: {
                    _owner: alice.address,
                    farming_pool: farming_pool.address
                }
            });

            const alice_passport_address = await booster_factory.call({
                method: 'derivePassport',
                params: {
                    _owner: alice.address
                }
            });

            alice_booster_account = await locklift.factory.getContract('BoosterAccount_V1');
            alice_booster_account.setAddress(alice_booster_account_address);
            alice_booster_account.name = 'Alice booster account';

            alice_passport = await locklift.factory.getContract('BoosterPassport');
            alice_passport.setAddress(alice_passport_address);
            alice_passport.name = 'Alice passport';

            await logContract(alice_booster_account);
            await logContract(alice_passport);
        });

        it('Check Alice passport details', async () => {
            const details = await alice_passport.call({ method: 'getDetails' });

            // console.log(details);

            expect(details._owner)
                .to.be.equal(alice.address, 'Wrong passport owner');
            expect(details._factory)
                .to.be.equal(booster_factory.address, 'Wrong passport factory');
            expect(details._version)
                .to.be.bignumber.equal(1, 'Wrong passport version');
            expect(details._managers)
                .to.be.eql(await booster_factory.call({ method: 'managers' }), 'Wrong passport managers');
            expect(details._ping_balance)
                .to.be.bignumber.equal(0, 'Passport initial ping balance should be zero');

            expect(details._accounts)
                .to.have.property(alice_booster_account.address);

            const account = details._accounts[alice_booster_account.address];

            expect(account.last_ping)
                .to.be.bignumber.greaterThan(0, 'Wrong passport account last ping');
            expect(account.ping_frequency)
                .to.be.bignumber.equal(ping_frequency, 'Wrong passport account ping frequency');
            expect(account.ping_counter)
                .to.be.bignumber.equal(0, 'Wrong passport account ping counter');
            expect(account.auto_ping_enabled)
                .to.be.equal(true, 'Wrong passport auto ping status');
        });

        it('Check Alice booster account details', async () => {
            const details = await alice_booster_account.call({ method: 'getDetails' });

            expect(details._owner)
                .to.be.equal(alice.address, 'Wrong booster owner');
            expect(details._version)
                .to.be.bignumber.equal(1, 'Wrong booster version');
            expect(details._factory)
                .to.be.equal(booster_factory.address, 'Wrong booster factory');
            expect(details._farming_pool)
                .to.be.equal(farming_pool.address, 'Wrong booster farming pool');

            logger.log(`Booster USDT wallet: ${details._wallets[USDT.address]}`);
            logger.log(`Booster USDC wallet: ${details._wallets[USDC.address]}`);
            logger.log(`Booster QUBE wallet: ${details._wallets[QUBE.address]}`);
            logger.log(`Booster BRIDGE wallet: ${details._wallets[BRIDGE.address]}`);
            logger.log(`Booster LP wallet: ${details._wallets[LP.address]}`);
        });

        it('Check Alice booster account initialized', async () => {
            const initialized = await alice_booster_account.call({ method: 'isInitialized' });

            expect(initialized)
                .to.be.equal(true, 'Alice account not initialized');
        });
    });

    describe('Alice uses booster', async () => {
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

                booster_factory,
                alice_passport,
                alice_booster_account,
            );

            // for (const contract of metricManager.contracts) {
            //     await logContract(contract);
            // }
        });

        it('Alice transfers some LP to the booster account', async () => {
            const wallet = await LP.wallet(alice);

            const amount = (await wallet.balance()).div(2).toFixed();

            const payload = await alice_booster_account.call({
                method: 'encodeTokenDepositPayload',
                params: {
                    update_frequency: false,
                    frequency: 0,
                    update_max_ping_price: false,
                    max_ping_price: 0,
                    update_slippage: false,
                    _slippage: 0,
                    toggle_auto_ping: false,
                    toggle_auto_reinvestment: false
                }
            });

            const tx = await alice.runTarget({
                contract: wallet.wallet,
                method: 'transfer',
                params: {
                    amount,
                    recipient: alice_booster_account.address,
                    deployWalletValue: 0,
                    remainingGasTo: alice.address,
                    notify: true,
                    payload
                },
                value: locklift.utils.convertCrystal(3, 'nano'),
            });

            await sleep(1000);

            logger.log(`Alice first LP deposit to booster tx: ${tx.transaction.id}`);

            const details = await alice_booster_account.call({ method: 'getDetails' });

            expect(details._balances[LP.address])
                .to.be.bignumber.equal(0, 'Booster LP balance should be zero');
            expect(details._received[LP.address])
                .to.be.bignumber.equal(amount, 'Booster LP received should be positive');
        });

        it('Check Alice booster has position in farming', async () => {
            const events = await farming_pool.getEvents('Deposit');
            const details = await alice_booster_account.call({ method: 'getDetails' });

            expect(events)
                .to.have.lengthOf(1, 'Wrong farming deposits amount');

            const [event] = events;

            expect(event.value.user)
                .to.be.equal(alice_booster_account.address, 'Wrong farming deposit author');
            expect(event.value.amount)
                .to.be.bignumber.equal(details._received[LP.address], 'Wrong farming deposit amount');

            // Save Alice booster user data
            alice_booster_account_user_data = await locklift.factory.getContract('UserDataV3');
            alice_booster_account_user_data.setAddress(details._user_data);
            alice_booster_account_user_data.name = 'Alice booster user data';

            metricManager.addContract(alice_booster_account_user_data);

            await logContract(alice_booster_account_user_data);
        });

        describe('First ping (by manager, zero price)', async () => {
            let _details, _position;

            it('Sleep 10 seconds to achieve farming rewards', async () => {
                await sleep(20 * 1000);
            });

            it('Save metrics before ping', async () => {
                _details = await alice_booster_account.call({ method: 'getDetails' });
                _position = await alice_booster_account_user_data.call({ method: 'getDetails' });
            });

            it('Ping (zero price)', async () => {
                const tx = await alice_passport.run({
                    method: 'pingByManager',
                    params: {
                        account: alice_booster_account.address,
                        price: 0,
                        counter: 0
                    },
                    keyPair: manager1
                });

                logger.success(`First ping tx (claim & reinvest rewards): ${tx.transaction.id}`);

                logger.log('Sleep a little');
                await sleep(5 * 1000);
            });

            it('Check booster virtual balances', async () => {
                const details = await alice_booster_account.call({ method: 'getDetails' });
                const position = await alice_booster_account_user_data.call({ method: 'getDetails' });

                expect(details._received[BRIDGE.address])
                    .to.be.bignumber.greaterThan(_details._received[BRIDGE.address], 'Booster should receive BRIDGE after ping')
                    .to.be.bignumber.greaterThan(0, 'Booster should receive BRIDGE reward');

                expect(details._received[QUBE.address])
                    .to.be.bignumber.greaterThan(_details._received[QUBE.address], 'Booster should receive BRIDGE after ping')
                    .to.be.bignumber.greaterThan(0, 'Booster should receive QUBE reward');

                expect(details._received[USDT.address])
                    .to.be.bignumber.greaterThan(_details._received[USDT.address], 'Booster should receive USDT after ping')
                    .to.be.bignumber.greaterThan(0, 'Booster should receive USDT after swap');

                expect(details._received[USDC.address])
                    .to.be.bignumber.greaterThan(_details._received[USDC.address], 'Booster should receive BRIDGE after ping')
                    .to.be.bignumber.greaterThan(0, 'Booster should receive USDC after swap');

                expect(details._received[details._lp])
                    .to.be.bignumber.greaterThan(_details._received[details._lp], 'Booster should receive LP after ping')
                    .to.be.bignumber.greaterThan(0, 'Booster should receive LP')
                    .to.be.bignumber.equal(position.amount, 'Booster should deposit all LP to farming');
            });
        });

        describe('Second ping (by Alice)', async () => {
            let details_before_ping;
            let position_before_ping;

            it('Sleep 10 seconds to achieve farming rewards', async () => {
                await sleep(10 * 1000);
            });

            it('Ping', async () => {
                details_before_ping = await alice_booster_account.call({ method: 'getDetails' });
                position_before_ping = await alice_booster_account_user_data.call({ method: 'getDetails' });

                const tx = await alice.runTarget({
                    contract: alice_passport,
                    method: 'pingByOwner',
                    params: {
                        _accounts: [alice_booster_account.address],
                        _counters: [1],
                        ping_value: locklift.utils.convertCrystal(2, 'nano')
                    },
                    value: locklift.utils.convertCrystal(3, 'nano')
                });

                logger.success(`Second ping by Alice tx: ${tx.transaction.id}`);

                await sleep(3000);
            });

            it('Check ping succeeded', async () => {
                const details = await alice_booster_account.call({ method: 'getDetails' });
                const position = await alice_booster_account_user_data.call({ method: 'getDetails' });

                expect(position.amount)
                    .to.be.bignumber.greaterThan(position_before_ping.amount, 'Booster farming LP balance should increase')
            });
        });

        describe('Alice adds LP tokens to her booster account', async () => {
            let position_before_transfer;

            it('Alice sends LPs to booster', async () => {
                position_before_transfer = await alice_booster_account_user_data.call({ method: 'getDetails' });

                const wallet = await LP.wallet(alice);

                const amount = await wallet.balance();

                const payload = await alice_booster_account.call({
                    method: 'encodeTokenDepositPayload',
                    params: {
                        update_frequency: false,
                        frequency: 0,
                        update_max_ping_price: false,
                        max_ping_price: 0,
                        update_slippage: false,
                        _slippage: 0,
                        toggle_auto_ping: false,
                        toggle_auto_reinvestment: false
                    }
                });

                const tx = await alice.runTarget({
                    contract: wallet.wallet,
                    method: 'transfer',
                    params: {
                        amount,
                        recipient: alice_booster_account.address,
                        deployWalletValue: 0,
                        remainingGasTo: alice.address,
                        notify: true,
                        payload
                    },
                    value: locklift.utils.convertCrystal(3, 'nano'),
                });

                await sleep(1000);

                logger.log(`Alice second LP deposit to booster tx: ${tx.transaction.id}`);
            });

            it('Check booster position increased', async () => {
                const position = await alice_booster_account_user_data.call({ method: 'getDetails' });

                expect(position.amount)
                    .to.be.bignumber.greaterThan(position_before_transfer.amount, 'Booster farming LP balance should increase')
            });
        });

        describe('Alice sends tokens to her booster account', async () => {
            const amount = 10_000;

            it('Mint tokens to Alice', async () => {
                await USDT.mint(amount, alice);
                // await USDC.mint(amount, alice);
                await BRIDGE.mint(amount, alice);
                // await QUBE.mint(amount, alice);
            });

            it('Alice sends USDT to booster', async () => {
                const details_before_deposit = await alice_booster_account.call({ method: 'getDetails' });
                const position_before_deposit = await alice_booster_account_user_data.call({ method: 'getDetails' });

                const wallet = await USDT.wallet(alice);

                const payload = await alice_booster_account.call({
                    method: 'encodeTokenDepositPayload',
                    params: {
                        update_frequency: false,
                        frequency: 0,
                        update_max_ping_price: false,
                        max_ping_price: 0,
                        update_slippage: false,
                        _slippage: 0,
                        toggle_auto_ping: false,
                        toggle_auto_reinvestment: false
                    }
                });

                const tx = await alice.runTarget({
                    contract: wallet.wallet,
                    method: 'transfer',
                    params: {
                        amount,
                        recipient: alice_booster_account.address,
                        deployWalletValue: 0,
                        remainingGasTo: alice.address,
                        notify: true,
                        payload
                    },
                    value: locklift.utils.convertCrystal(1, 'nano'),
                });

                logger.log(`Transfer tx: ${tx.transaction.id}`);

                const details = await alice_booster_account.call({ method: 'getDetails' });
                const position = await alice_booster_account_user_data.call({ method: 'getDetails' });

                expect(details._balances[USDT.address])
                    .to.be.bignumber.equal(0, 'Booster should swap received token');
                expect(details._received[USDT.address])
                    .to.be.bignumber
                    .equal((new BigNumber(details_before_deposit._received[USDT.address])).plus(amount), 'Wrong received amount');
                expect(details._received[LP.address])
                    .to.be.bignumber.greaterThan(details_before_deposit._received[LP.address], 'Booster LP should increase');
                expect(position.amount)
                    .to.be.bignumber.greaterThan(position_before_deposit.amount, 'Booster farming position should increase');
            });

            it('Alice sends USDC to booster', async () => {

            });

            it('Alice sends BRIDGE to booster', async () => {
                const details_before_deposit = await alice_booster_account.call({ method: 'getDetails' });
                const position_before_deposit = await alice_booster_account_user_data.call({ method: 'getDetails' });

                const wallet = await BRIDGE.wallet(alice);

                const payload = await alice_booster_account.call({
                    method: 'encodeTokenDepositPayload',
                    params: {
                        update_frequency: false,
                        frequency: 0,
                        update_max_ping_price: false,
                        max_ping_price: 0,
                        update_slippage: false,
                        _slippage: 0,
                        toggle_auto_ping: false,
                        toggle_auto_reinvestment: false
                    }
                });

                const tx = await alice.runTarget({
                    contract: wallet.wallet,
                    method: 'transfer',
                    params: {
                        amount,
                        recipient: alice_booster_account.address,
                        deployWalletValue: 0,
                        remainingGasTo: alice.address,
                        notify: true,
                        payload
                    },
                    value: locklift.utils.convertCrystal(1, 'nano'),
                });

                logger.log(`Transfer tx: ${tx.transaction.id}`);

                const details = await alice_booster_account.call({ method: 'getDetails' });
                const position = await alice_booster_account_user_data.call({ method: 'getDetails' });

                // - Booster receives some additional BRIDGE as a reward
                // expect(details._balances[BRIDGE.address])
                //     .to.be.bignumber.equal(0, 'Booster should swap received token');

                await sleep(2000);

                expect(details._received[BRIDGE.address])
                    .to.be.bignumber
                    .greaterThan(
                        details_before_deposit._received[BRIDGE.address],
                        'Wrong received amount'
                    );

                expect(details._received[LP.address])
                    .to.be.bignumber.greaterThan(details_before_deposit._received[LP.address], 'Booster LP should increase');
                expect(position.amount)
                    .to.be.bignumber.greaterThan(position_before_deposit.amount, 'Booster farming position should increase');
            });

            it('Alice sends QUBE to booster', async () => {

            });
        });

        describe('Alice pauses booster token processing', async () => {
            it('Alice pauses booster token processing', async () => {
                await alice.runTarget({
                    contract: alice_booster_account,
                    method: 'toggleAutoReinvestment',
                    value: locklift.utils.convertCrystal(1, 'nano')
                });

                expect(await alice_booster_account.call({ method: 'auto_reinvestment' }))
                    .to.be.equal(false);
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
                        amount: lp_to_withdraw,
                        toggle_auto_reinvestment: false
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
                await sleep(20 * 1000);

                const tx = await alice_passport.run({
                    method: 'pingByManager',
                    params: {
                        account: alice_booster_account.address,
                        price: 0,
                        counter: (await alice_passport.call({ method: 'accounts' }))[alice_booster_account.address].ping_counter
                    },
                    keyPair: manager2
                });

                logger.success(`Third ping tx (claim rewards): ${tx.transaction.id}`);

                await sleep(2000);

                const alice_qube = await QUBE.wallet(alice);
                const alice_bridge = await BRIDGE.wallet(alice);

                expect(await alice_qube.balance())
                    .to.be.bignumber.greaterThan(0, 'Alice should receive QUBE reward');
                expect(await alice_bridge.balance())
                    .to.be.bignumber.greaterThan(0, 'Alice should receive BRIDGE reward');
            });

            it('Alice unpauses booster token processing', async () => {
                await alice.runTarget({
                    contract: alice_booster_account,
                    method: 'toggleAutoReinvestment',
                    value: locklift.utils.convertCrystal(1, 'nano')
                });

                expect(await alice_booster_account.call({ method: 'auto_reinvestment' }))
                    .to.be.equal(true);
            });
        });

        describe('Claim rewarder fees', async () => {
            let details_before_skim;

            it('Get rewarder wallets', async () => {
                const rewarder_qube = await QUBE.wallet(rewarder);
                rewarder_qube.wallet.name = 'Rewarder QUBE wallet';
                const rewarder_bridge = await BRIDGE.wallet(rewarder);
                rewarder_bridge.wallet.name = 'Rewarder BRIDGE wallet';
                const rewarder_lp = await LP.wallet(rewarder);
                rewarder_lp.wallet.name = 'Rewarder LP wallet';

                metricManager.addContract(rewarder_qube.wallet);
                metricManager.addContract(rewarder_bridge.wallet);
                metricManager.addContract(rewarder_lp.wallet);
            });

            it('Check booster recorded fees', async () => {
                details_before_skim = await alice_booster_account.call({ method: 'getDetails' });

                expect(details_before_skim._fees[QUBE.address])
                    .to.be.bignumber.greaterThan(0, 'QUBE fees should be non-zero');
                expect(details_before_skim._fees[BRIDGE.address])
                    .to.be.bignumber.greaterThan(0, 'BRIDGE fees should be non-zero');
                expect(details_before_skim._fees[LP.address])
                    .to.be.bignumber.greaterThan(0, 'LP fees should be zero');

                expect(details_before_skim._fees[USDT.address])
                    .to.be.bignumber.equal(0, 'USDT fees should be zero');
                expect(details_before_skim._fees[USDC.address])
                    .to.be.bignumber.equal(0, 'USDC fees should be zero');
            });

            it('Skim fees', async () => {
                const tx = await god.runTarget({
                    contract: booster_factory,
                    method: 'skimFees',
                    params: {
                        accounts: [alice_booster_account.address]
                    },
                    value: locklift.utils.convertCrystal(10, 'nano')
                });

                logger.success(`Skim tx (skim fees): ${tx.transaction.id}`);

                await sleep(1000);
            });

            it('Check rewarder received fees', async () => {
                const rewarder_received = await rewarder.call({ method: 'received' });

                expect(rewarder_received[QUBE.address])
                    .to.be.bignumber.equal(
                        details_before_skim._fees[QUBE.address],
                        'Rewarder QUBE balance should be non-zero'
                    );

                expect(rewarder_received[BRIDGE.address])
                    .to.be.bignumber.equal(
                        details_before_skim._fees[BRIDGE.address],
                        'Rewarder BRIDGE balance should be non-zero'
                    );

                expect(rewarder_received[LP.address])
                    .to.be.bignumber.equal(
                        details_before_skim._fees[LP.address],
                        'Rewarder LP balance should be non-zero'
                    );
            });

            it('Check booster recorded fees are zero after skim', async () => {
                const details = await alice_booster_account.call({ method: 'getDetails' });

                expect(details._fees[QUBE.address])
                    .to.be.bignumber.equal(0, 'QUBE fees should be zero');
                expect(details._fees[BRIDGE.address])
                    .to.be.bignumber.equal(0, 'BRIDGE fees should be zero');
                expect(details._fees[USDT.address])
                    .to.be.bignumber.equal(0, 'USDT fees should be zero');
                expect(details._fees[USDC.address])
                    .to.be.bignumber.equal(0, 'USDC fees should be zero');
                expect(details._fees[LP.address])
                    .to.be.bignumber.equal(0, 'LP fees should be zero');
            });
        });

        describe('Ping booster with non-zero price', async () => {
            const alice_booster_initial_balance = Math.floor(alice_ping_initial_balance / 2);

            const price = max_ping_price - 1;

            it('Alice tops up the booster ping balance', async () => {
                const alice_ping = await PING.wallet(alice);

                const payload = await booster_factory.call({
                    method: 'encodePingTopUp',
                    params: {
                        deploy_passport: false,
                        max_ping_price: 0,
                    }
                });

                await alice_ping.transfer(
                    alice_booster_initial_balance,
                    booster_factory.address,
                    payload
                );

                expect(await alice_passport.call({ method: 'ping_balance' }))
                    .to.be.bignumber.equal(alice_booster_initial_balance, 'Wrong Alice booster ping balance');
                expect(await booster_factory.call({ method: 'ping_spent' }))
                    .to.be.bignumber.equal(0, 'Booster factory spent ping should be zero');
            });

            it('Sleep a little to achieve rewards', async () => {
                await sleep(20 * 1000);
            });

            it('Ping', async () => {
                const _details = await alice_booster_account_user_data.call({ method: 'getDetails' });

                const tx = await alice_passport.run({
                    method: 'pingByManager',
                    params: {
                        account: alice_booster_account.address,
                        price,
                        counter: (await alice_passport.call({ method: 'accounts' }))[alice_booster_account.address].ping_counter
                    },
                    keyPair: manager2
                });

                logger.success(`Fourth ping tx (non-zero price): ${tx.transaction.id}`);

                await sleep(3000);

                const details = await alice_booster_account_user_data.call({ method: 'getDetails' });

                expect(details.amount)
                    .to.be.bignumber.greaterThan(_details.amount, 'Booster farming LP balance should increase');
                expect(await booster_factory.call({ method: 'ping_spent' }))
                    .to.be.bignumber.equal(price, 'Booster factory spent ping should increase by ping price');
            });

            it('Alice withdraws ping tokens', async () => {

            });

            it('God claims PINGs from the factory', async () => {
                const wallet = await PING.wallet(god);

                const balance_before_claim = await wallet.balance();
                const ping_spent = await booster_factory.call({ method: 'ping_spent' });

                await god.runTarget({
                    contract: booster_factory,
                    method: 'claimSpentPingTokens',
                    value: locklift.utils.convertCrystal(10, 'nano')
                });

                expect(await wallet.balance())
                    .to.be.bignumber.equal(balance_before_claim.plus(ping_spent), 'Wrong God ping balance after factory claim');
            });
        });

        describe('Send wrong token to the booster account', async () => {
            let dummy;

            const amount = 100;

            it('Setup dummy token and mint it to Alice', async () => {
                dummy = await setupTokenRoot('Dummy token', 'DUMMY', god);

                const tx = await god.runTarget({
                    contract: dummy.token,
                    method: 'mint',
                    params: {
                        amount,
                        recipient: alice.address,
                        deployWalletValue: locklift.utils.convertCrystal(0.2, 'nano'),
                        remainingGasTo: god.address,
                        notify: false,
                        payload: ''
                    },
                    value: locklift.utils.convertCrystal(3, 'nano'),
                });

                logger.log(`Dummy mint tx: ${tx.transaction.id}`);
            });

            it('Transfer token to the booster account', async () => {
                const alice_dummy = await dummy.wallet(alice);

                const tx = await alice.runTarget({
                    contract: alice_dummy.wallet,
                    method: 'transfer',
                    params: {
                        amount,
                        recipient: alice_booster_account.address,
                        deployWalletValue: locklift.utils.convertCrystal(0.2, 'nano'),
                        remainingGasTo: alice.address,
                        notify: true,
                        payload: ""
                    },
                    value: locklift.utils.convertCrystal(10, 'nano'),
                });

                logger.log(`Dummy token transfer tx: ${tx.transaction.id}`);
            });

            it('Check token refunded', async () => {
                const alice_dummy = await dummy.wallet(alice);
                const booster_dummy = await dummy.wallet(alice_booster_account);

                expect(await alice_dummy.balance())
                    .to.be.bignumber.equal(amount, 'Alice should receive dummy token back');
                expect(await booster_dummy.balance())
                    .to.be.bignumber.equal(0, 'Booster should refund tokens back');
            });
        });

        describe('Final metrics', async () => {
            it('Balances', async () => {
                await logContract(booster_factory);
                await logContract(alice_passport);
                await logContract(alice_booster_account);
                await logContract(rewarder);
                await logContract(farming_pool.pool);
                await logContract(alice_booster_account_user_data);
            });
        });
    });
});
