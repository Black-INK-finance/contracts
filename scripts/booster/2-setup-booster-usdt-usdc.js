const logger = require('mocha-logger');
const prompts = require('prompts');
const ora = require('ora');
const { isValidTonAddress, logContract } = require('../../test/utils');


const main = async () => {
    const [keyPair] = await locklift.keys.getKeyPairs();
    const Account = await locklift.factory.getAccount('Wallet');

    const response = await prompts([
        {
            type: 'text',
            name: 'owner',
            message: 'Fabric owner',
            validate: value => isValidTonAddress(value) ? true : 'Invalid address',
            initial: '0:fafa4c591a83125c35d0f4c1b0bcf5fafdb6c8fea186df10e1e615f49336e342',
        },
        {
            type: 'text',
            name: 'manager',
            message: 'Booster manager (pings booster accounts)',
            validate: value => isValidTonAddress(value) ? true : 'Invalid address',
            initial: '0:fafa4c591a83125c35d0f4c1b0bcf5fafdb6c8fea186df10e1e615f49336e342',
        },
        {
            type: 'number',
            name: 'ping_frequency',
            message: 'Booster account ping frequency (no less than 15 minutes)',
            initial: 15 * 60
        }
    ]);

    const BoosterFactory = await locklift.factory.getContract('BoosterFactory');
    const BoosterManager = await locklift.factory.getContract('BoosterManager');
    const BoosterBuyBack = await locklift.factory.getContract('BoosterBuyBack');
    const BoosterAccount = await locklift.factory.getContract('BoosterAccount_V1');
    const BoosterAccountPlatform = await locklift.factory.getContract('BoosterAccountPlatform');

    const spinner = ora('Deploying temp owner').start();
    const user = await locklift.giver.deployContract({
        contract: Account,
        constructorParams: {},
        initParams: {
            _randomNonce: locklift.utils.getRandomNonce()
        },
        keyPair,
    }, locklift.utils.convertCrystal(20, 'nano'));
    user.setKeyPair(keyPair);
    spinner.stop();

    await logContract(user);

    spinner.start('Deploying factory');
    const factory = await locklift.giver.deployContract({
        contract: BoosterFactory,
        constructorParams: {
            _owner: user.address,
            _manager: response.manager,
            _account: BoosterAccount.code,
            _account_platform: BoosterAccountPlatform.code
        }
    }, locklift.utils.convertCrystal(5, 'nano'));
    spinner.stop();

    await logContract(factory);

    spinner.start('Adding USDT/USDC farming (rewards: QUBE,WEVER)');

    const farming_pool = '0:60efb0dbae8fddadb844d3e5a2d6ece2739d0fe38dd5b4ce7f60f53a2d2b676f';
    const lp_address = '0:1ddd1a0a7d6ee3cef8ccb9e6aa02f5c142658522ddd40f21ae7160177ced0e12';

    const dex_pair_USDT_USDC = '0:b3b454752cf29575ba0f79cd6ee7fb5ed5fe2ad06555e28c12f7ee88835d728f';
    const dex_pair_WEVER_USDT = '0:771e3d124c7a824d341484718fcf1af03dd4ba1baf280adeb0663bb030ce2bf9';
    const dex_pair_QUBE_WEVER = '0:c8021e99e5329cd863ed206e2729be28586dc2ab398ed4d5f2bbddf2f44d8b01';

    const USDT = '0:a519f99bb5d6d51ef958ed24d337ad75a1c770885dcd42d51d6663f9fcdacfb2';
    const USDC = '0:c37b3fafca5bf7d3704b081fde7df54f298736ee059bf6d32fac25f5e6085bf6';
    const QUBE = '0:9f20666ce123602fd7a995508aeaa0ece4f92133503c0dfbd609b3239f3901e2';
    const WEVER = '0:a49cd4e158a9a15555e624759e2e4e766d22600b7800d891e46f9291f044a93d';

    await user.runTarget({
        contract: factory,
        method: 'addFarming',
        params: {
            farming_pool,
            lp: lp_address,
            pair: dex_pair_USDT_USDC,
            left: USDT,
            right: USDC,
            rewards: [WEVER, QUBE],
            swaps: {
                [QUBE]: {
                    token: WEVER,
                    pair: dex_pair_QUBE_WEVER
                },
                [WEVER]: {
                    token: USDT,
                    pair: dex_pair_WEVER_USDT
                }
            },
            recommended_ping_frequency: 60 * 30, // 30 minutes
            rewarder: response.owner,
            fee: 10
        },
        value: locklift.utils.convertCrystal(1, 'nano')
    });
    spinner.stop();

    spinner.start(`Deploy booster account for owner`);
    await user.runTarget({
        contract: factory,
        method: 'deployAccount',
        params: {
            _owner: response.owner,
            farming_pool,
            ping_frequency: response.ping_frequency
        },
        value: locklift.utils.convertCrystal(10.5, 'nano')
    });
    spinner.stop();

    const booster = await factory.call({
        method: 'deriveAccount',
        params: {
            _owner: response.owner,
            farming_pool
        }
    });

    logger.log(`Booster account: ${booster}`);

    spinner.start(`Transferring ownership to the owner`);
    await user.runTarget({
        contract: factory,
        method: 'transferOwnership',
        params: {
            newOwner: response.owner,
        },
    });
    spinner.stop();
};


main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
