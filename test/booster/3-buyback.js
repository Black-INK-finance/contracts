const {deployUser, setupTokenRoot, expect, setupDex, deployDexPair, DEX_CONTRACTS_PATH, logContract, Token, sleep,
    MetricManager
} = require("../utils");
const BigNumber = require("bignumber.js");
const logger = require("mocha-logger");


const god_supply = new BigNumber(1_000_000_000).pow(2);
let dex_token_factory, dex_root, dex_vault;


describe('Test buyback functionality', async function () {
    this.timeout(3000000000000);

    let metricManager;
    let god, alice, rewarder;
    let BRIDGE, QUBE, PING, LP;
    let dex_pair_QUBE_BRIDGE,dex_pair_BRIDGE_PING;

    const dex_pair_initial_supply = new BigNumber(10_000_000_000_000);
    const alice_initial_balance = new BigNumber(1_000);

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
    });

    describe('Setup tokens', async () => {
        it('Deploy tokens', async () => {
            BRIDGE = await setupTokenRoot('Bridge', 'BRIDGE', god);
            QUBE = await setupTokenRoot('FlatQube', 'QUBE', god);

            PING = await setupTokenRoot('Ping', 'PING', god);
        });

        it('Mint tokens to God', async () => {
            await QUBE.mint(god_supply, god);
            await BRIDGE.mint(god_supply, god);
            await PING.mint(god_supply, god);
        });

        it('Mint tokens to Alice', async () => {
            await QUBE.mint(alice_initial_balance, alice);
            await BRIDGE.mint(alice_initial_balance, alice);
            await PING.mint(alice_initial_balance, alice);
        });
    });

    describe('Setup Dex', async () => {
        it('Deploy token factory, dex root, dex vault', async () => {
            [dex_token_factory, dex_root, dex_vault] = await setupDex(god);
        });

        it('Deploy pairs', async () => {
            [dex_pair_QUBE_BRIDGE] = await deployDexPair(god, dex_root, QUBE, BRIDGE);
            [dex_pair_BRIDGE_PING] = await deployDexPair(god, dex_root, BRIDGE, PING);
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
                for (const pair of [dex_pair_QUBE_BRIDGE, dex_pair_BRIDGE_PING]) {
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
                for (const pair of [dex_pair_QUBE_BRIDGE, dex_pair_BRIDGE_PING]) {
                    const balances = await pair.call({ method: 'getBalances' });

                    expect(balances.left_balance)
                        .to.be.bignumber.equal(dex_pair_initial_supply, `Wrong left balance for ${pair.address}`);
                    expect(balances.right_balance)
                        .to.be.bignumber.equal(dex_pair_initial_supply, `Wrong right balance for ${pair.address}`);
                }
            });

            it('Setup QUBE/BRIDGE LP token', async () => {
                const token_roots = await dex_pair_QUBE_BRIDGE.call({
                    method: 'getTokenRoots',
                });

                LP = await Token.from_addr(token_roots.lp, alice);
                LP.token.name = 'Token root [LP QUBE/BRIDGE]';
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
                        ]
                    }
                });
            });

            it('Initialize swap rules for QUBE and BRIDGE', async () => {
                await god.runTarget({
                    contract: rewarder,
                    method: 'setTokenSwap',
                    params: {
                        token: QUBE.address,
                        swap: {
                            token: BRIDGE.address,
                            pair: dex_pair_QUBE_BRIDGE.address,
                            minToSwap: 0
                        },
                    }
                });

                await god.runTarget({
                    contract: rewarder,
                    method: 'setTokenSwap',
                    params: {
                        token: BRIDGE.address,
                        swap: {
                            token: PING.address,
                            pair: dex_pair_BRIDGE_PING.address,
                            minToSwap: 200
                        }
                    }
                });
            });

            it('Setup metric manager', async () => {
                metricManager = new MetricManager(alice, god, rewarder);
            });
        });

        describe('Alice transfers QUBE to the rewarder (should be swapped immediately)', async () => {
            it('Alice transfers 100 QUBE', async () => {
                const alice_qube = await QUBE.wallet(alice);

                const tx = await alice.runTarget({
                    contract: alice_qube.wallet,
                    method: 'transfer',
                    params: {
                        amount: 100,
                        recipient: rewarder.address,
                        deployWalletValue: 0,
                        remainingGasTo: alice.address,
                        notify: true,
                        payload: ""
                    },
                    value: locklift.utils.convertCrystal(0.5, 'nano'),
                });

                logger.log(`Alice transfers QUBE: ${tx.transaction.id}`);
            });

            it('Check rewarder received QUBE and swapped them into BRIDGE', async () => {
                const received = await rewarder.call({ method: 'received' });
                const balances = await rewarder.call({ method: 'balances' });

                expect(received[QUBE.address])
                    .to.be.bignumber.equal(100, 'Rewarder should receive QUBE');
                expect(received[BRIDGE.address])
                    .to.be.bignumber.greaterThan(0, 'Rewarder should receive BRIDGE from swap');

                expect(balances[QUBE.address])
                    .to.be.bignumber.equal(0, 'Rewarder should has zero QUBE balance');
                expect(balances[BRIDGE.address])
                    .to.be.bignumber.equal(received[BRIDGE.address], 'Rewarder should has received BRIDGE balance');
            });
        });

        describe('Alice transfers BRIDGE to the rewarder (buyback triggerred)', async () => {
            let received_before_transfer;

            it('Alice transfers 200 BRIDGE', async () => {
                received_before_transfer = await rewarder.call({ method: 'received' });

                const alice_bridge = await BRIDGE.wallet(alice);

                const tx = await alice.runTarget({
                    contract: alice_bridge.wallet,
                    method: 'transfer',
                    params: {
                        amount: 200,
                        recipient: rewarder.address,
                        deployWalletValue: 0,
                        remainingGasTo: alice.address,
                        notify: true,
                        payload: ""
                    },
                    value: locklift.utils.convertCrystal(0.5, 'nano'),
                });

                logger.log(`Alice transfers BRIDGE: ${tx.transaction.id}`);
            });

            it('Check rewarder received BRIDGE and swapped them into PING', async () => {
                const balances = await rewarder.call({ method: 'balances' });
                const received = await rewarder.call({ method: 'received' });

                expect(balances[QUBE.address])
                    .to.be.bignumber.equal(0, 'Rewarder should has zero QUBE balance');
                expect(balances[BRIDGE.address])
                    .to.be.bignumber.equal(0, 'Rewarder should has zero BRIDGE balance');
                expect(balances[PING.address])
                    .to.be.bignumber.greaterThan(0, 'Rewarder should has non-zero PING balance');

                expect(received[PING.address])
                    .to.be.bignumber.equal(balances[PING.address], 'Rewarder should has non-zero PING received');
                expect(received[BRIDGE.address])
                    .to.be.bignumber.equal(
                        (new BigNumber(received_before_transfer[BRIDGE.address])).plus(200),
                        'Rewarder should has increased BRIDGE received'
                    );
                expect(received[QUBE.address])
                    .to.be.bignumber.equal(
                        new BigNumber(received_before_transfer[QUBE.address]),
                        'Rewarder should has same QUBE received'
                    );
            });
        });

        describe('Claim 1 PING', async () => {
            let balance_before_claim;
            let god_ping_balance_before_claim;

            it('God claims 1 PING from rewarder', async () => {
                balance_before_claim = await rewarder.call({ method: 'balances' });

                const god_ping = await PING.wallet(god);
                god_ping_balance_before_claim = await god_ping.balance();

                await god.runTarget({
                    contract: rewarder,
                    method: 'claim',
                    params: {
                        root: PING.address,
                        _amount: 1
                    }
                });
            });

            it('Check 1 PING claimed', async () => {
                const balances = await rewarder.call({ method: 'balances' });

                expect(balances[PING.address])
                    .to.be.bignumber.equal(
                        (new BigNumber(balance_before_claim[PING.address])).minus(1),
                        'Rewarder PING balance should decrease by 1'
                    );

                const god_ping = await PING.wallet(god);

                expect(await god_ping.balance())
                    .to.be.bignumber.equal(
                        god_ping_balance_before_claim.plus(1),
                        'Wrong god balance after 1 PING claim'
                    );
            });
        });

        describe('Claim rest PINGs from rewarder', async () => {
            let balance_before_claim;
            let god_ping_balance_before_claim;

            it('God claims all PINGs', async () => {
                balance_before_claim = await rewarder.call({ method: 'balances' });

                const god_ping = await PING.wallet(god);
                god_ping_balance_before_claim = await god_ping.balance();

                await god.runTarget({
                    contract: rewarder,
                    method: 'claim',
                    params: {
                        root: PING.address,
                        _amount: 0
                    }
                });
            });

            it('Check all PINGs claimed', async () => {
                const balances = await rewarder.call({ method: 'balances' });

                expect(balances[PING.address])
                    .to.be.bignumber.equal(0, 'Rewarder should has zero PING balance');

                const god_ping = await PING.wallet(god);

                expect(await god_ping.balance())
                    .to.be.bignumber.equal(
                        (new BigNumber(god_ping_balance_before_claim)).plus(balance_before_claim[PING.address]),
                        'God should receive all PINGs'
                    );
            });
        });
    });
});
