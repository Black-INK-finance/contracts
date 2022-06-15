const {
    deployUser,
    logContract,
    setupTokenRoot,
    setupFabric,
    expect
} = require("../utils");
const logger = require('mocha-logger');


describe('Test booster updatability', async function() {
    this.timeout(3000000000000);

    let god, alice, rewarder;
    let manager;

    let left, right, lp, reward, ping;
    let farming_factory, farming_pool;

    let booster_factory, alice_booster_account, alice_passport;

    const farmStart = Math.floor(Date.now() / 1000);

    it('Setup actors', async () => {
        god = await deployUser('God');
        alice = await deployUser('Alice');
        rewarder = await deployUser('Rewarder');
    });

    it('Setup booster manager', async () => {
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

    it('Setup tokens', async () => {
        left = await setupTokenRoot('Dummy Left', 'DUMMY_LEFT', god);
        right = await setupTokenRoot('Dummy Right', 'DUMMY_RIGHT', god);
        lp = await setupTokenRoot('Dummy LP', 'DUMMY_LP', god);
        reward = await setupTokenRoot('Dummy Reward', 'DUMMY_REWARD', god);
        ping = await setupTokenRoot('Dummy ping', 'DUMMY_PING', god);
    });

    it('Setup booster factory', async () => {
        const [manager1] = await locklift.keys.getKeyPairs();

        const BoosterFactory = await locklift.factory.getContract('BoosterFactory');
        const BoosterAccountPlatform = await locklift.factory.getContract('BoosterAccountPlatform')
        const BoosterAccount = await locklift.factory.getContract('BoosterAccount_V1');
        const BoosterPassportPlatform = await locklift.factory.getContract('BoosterPassportPlatform');
        const BoosterPassport = await locklift.factory.getContract('BoosterPassport');

        booster_factory = await locklift.giver.deployContract({
            contract: BoosterFactory,
            constructorParams: {
                _owner: god.address,
                _managers: [`0x${manager1.public}`],
                _rewarder: rewarder.address,
                _ping_token_root: ping.address,
                _account_platform: BoosterAccountPlatform.code,
                _account_implementation: BoosterAccount.code,
                _passport_platform: BoosterPassportPlatform.code,
                _passport_implementation: BoosterPassport.code
            },
        });

        await logContract(booster_factory);
    });

    it('Add dummy farming', async () => {
        farming_factory = await setupFabric(god, 2, 2, 2);
        farming_pool = await farming_factory.deployPool({
            pool_owner: god,
            reward_rounds: [
                {
                    startTime: 10,
                    rewardPerSecond: [20]
                }
            ],
            tokenRoot: lp.address,
            rewardTokenRoot: [reward.address],
            vestingPeriod: 0,
            vestingRatio: 0,
            withdrawAllLockPeriod: 0
        });

        await god.runTarget({
            contract: booster_factory,
            method: 'addFarming',
            params: {
                dex: locklift.utils.zeroAddress,
                farming_pool: farming_pool.address,
                lp: lp.address,
                pair: locklift.utils.zeroAddress,
                left: left.address,
                right: right.address,
                rewards: [reward.address],
                swaps: {
                    [reward.address]: {
                        token: left.address,
                        pair: locklift.utils.zeroAddress
                    }
                },
                recommended_ping_frequency: 20 * 60, // 20 minutes
                rewarder: rewarder.address,
                reward_fee: 10,
                lp_fee: 0,
                ping_value: locklift.utils.convertCrystal(2, 'nano')
            }
        });
    });

    describe('Upgrade booster factory', async () => {
        let details_before_upgrade;

        it('Save old booster factory state', async () => {
            details_before_upgrade = await booster_factory.call({ method: 'getDetails' });
        });

        it('Upgrade factory', async () => {
            const BoosterFactory = await locklift.factory.getContract('BoosterFactory');

            await god.runTarget({
                contract: booster_factory,
                method: 'upgrade',
                params: {
                    code: BoosterFactory.code
                }
            });
        });

        it('Check new factory state', async () => {
            const details = await booster_factory.call({ method: 'getDetails' });

            expect(details._version)
                .to.be.bignumber.equal(details_before_upgrade._version.plus(1), 'Wrong new factory version');
            expect(details._manager)
                .to.be.equal(details_before_upgrade._manager, 'Wrong new factory manager');
            expect(details._account)
                .to.be.equal(details_before_upgrade._account, 'Wrong new factory account code');
            expect(details._account_platform)
                .to.be.equal(details_before_upgrade._account_platform, 'Wrong new factory account platform code');
            expect(details._account_version)
                .to.be.bignumber.equal(details_before_upgrade._account_version, 'Wrong new factory account version');

            expect(details._farmings[farming_pool.address])
                .to.not.be.equal(undefined, 'Wrong new factory farming');

            expect(await booster_factory.call({ method: 'owner' }))
                .to.be.equal(god.address, 'Wrong new factory owner');
        });
    });

    describe('Upgrade booster manager', async () => {
        let details_before_upgrade;

        it('Save old booster manager state', async () => {
            details_before_upgrade = await manager.call({ method: 'getDetails' });
        });

        it('Upgrade booster manager', async () => {
            const BoosterManager = await locklift.factory.getContract('BoosterManager');

            await god.runTarget({
                contract: manager,
                method: 'upgrade',
                params: {
                    code: BoosterManager.code
                }
            });
        });

        it('Check new manager state', async () => {
            const details = await manager.call({ method: 'getDetails' });

            expect(details._version)
                .to.be.bignumber.equal(details_before_upgrade._version.plus(1), 'Wrong new manager version');
            expect(details._owner)
                .to.be.bignumber.equal(details_before_upgrade._owner, 'Wrong new manager owner');
            expect(details._internalOwner)
                .to.be.equal(god.address, 'Wrong new manager internal owner');
        });
    });

    describe('Upgrade booster account and passport', async () => {
        let details_before_upgrade;

        it('Create booster account', async () => {
            await alice.runTarget({
                contract: booster_factory,
                method: 'deployAccount',
                params: {
                    farming_pool: farming_pool.address,
                    ping_frequency: 60 * 20,
                    max_ping_price: 1000,
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

        it('Set new booster account in factory', async () => {
            const BoosterAccount = await locklift.factory.getContract('BoosterAccount_V2');

            const _account_version = await booster_factory.call({ method: 'account_version' });

            await god.runTarget({
                contract: booster_factory,
                method: 'upgradeAccountCode',
                params: {
                    _account_implementation: BoosterAccount.code
                }
            });

            expect(await booster_factory.call({ method: 'account_version' }))
                .to.be.bignumber.equal(_account_version.plus(1), 'Wrong factory account version after update');
        });

        it('Save old booster account state', async () => {
            details_before_upgrade = await alice_booster_account.call({ method: 'getDetails' });
        });

        it('Upgrade booster account', async () => {
            const tx = await god.runTarget({
                contract: booster_factory,
                method: 'upgradeAccounts',
                params: {
                    accounts: [alice_booster_account.address]
                },
                value: locklift.utils.convertCrystal(20, 'nano')
            });

            logger.success(`Alice booster account upgrade tx: ${tx.transaction.id}`);
        });

        it('Check new booster account state', async () => {
            const details = await alice_booster_account.call({ method: 'getDetails' });

            expect(details._version)
                .to.be.bignumber.equal(details_before_upgrade._version.plus(1), 'Wrong booster account version');
            expect(details._factory)
                .to.be.equal(details_before_upgrade._factory, 'Wrong booster account factory');
            expect(details._farming_pool)
                .to.be.equal(details_before_upgrade._farming_pool, 'Wrong booster account farming pool');
            expect(details._manager)
                .to.be.equal(details_before_upgrade._manager, 'Wrong booster account manager');
            expect(details._user_data)
                .to.be.equal(details_before_upgrade._user_data, 'Wrong booster account user data');
            expect(details._rewards)
                .to.be.eql(details_before_upgrade._rewards, 'Wrong booster account reward tokens');
            expect(details._rewarder)
                .to.be.equal(details_before_upgrade._rewarder, 'Wrong booster account rewarder');
            expect(details._reward_fee)
                .to.be.bignumber.equal(details_before_upgrade._reward_fee, 'Wrong booster account reward fee');
            expect(details._lp_fee)
                .to.be.bignumber.equal(details_before_upgrade._lp_fee, 'Wrong booster account reward fee');
        });
    });
});
