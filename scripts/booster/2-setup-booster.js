const logger = require('mocha-logger');
const prompts = require('prompts');
const ora = require('ora');
const { isValidTonAddress, logContract } = require('../../test/utils');
const BigNumber = require("bignumber.js");


const main = async () => {
    logger.log('Dont forget to check default values in the following contracts!!');
    logger.log('contracts/Gas.sol');
    logger.log('contracts/Constants.sol');

    const [key] = await locklift.keys.getKeyPairs();

    logger.log(`First pubkey: 0x${key.public}`);

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
            name: 'ping_token',
            message: 'Project token root (keeper rewards, buybacks, etc)',
            validate: value => isValidTonAddress(value) ? true : 'Invalid address',
        },
        {
            type: 'number',
            name: 'rewarder_value',
            message: 'Rewarder initial value in EVERs',
            initial: 20
        },
        {
            type: 'number',
            name: 'factory_value',
            message: 'Factory initial value in EVERs',
            initial: 50
        },
        {
            type: 'toggle',
            name: 'add_farming_pools',
            message: 'Add some farmings as a preset (cant do this with UI)',
            initial: true,
            active: 'yes',
            inactive: 'no'
        }
    ]);

    const BoosterFactory = await locklift.factory.getContract('BoosterFactory');
    const BoosterBuyBack = await locklift.factory.getContract('BoosterBuyBack');
    const BoosterAccountPlatform = await locklift.factory.getContract('BoosterAccountPlatform');
    const BoosterAccount = await locklift.factory.getContract('BoosterAccount_V1');
    const BoosterPassportPlatform = await locklift.factory.getContract('BoosterPassportPlatform');
    const BoosterPassport = await locklift.factory.getContract('BoosterPassport');


    const spinner = ora('Deploying buyback').start();
    const rewarder = await locklift.giver.deployContract({
        contract: BoosterBuyBack,
        constructorParams: {
            _owner: response.owner
        }
    }, locklift.utils.convertCrystal(response.rewarder_value, 'nano'));
    rewarder.name = 'Rewarder (BuyBack)';
    spinner.stop();

    await logContract(rewarder);

    spinner.start('Deploying temp owner');

    const [keyPair] = await locklift.keys.getKeyPairs();
    const Account = await locklift.factory.getAccount('Wallet');
    const user = await locklift.giver.deployContract({
        contract: Account,
        constructorParams: {},
        initParams: {
            _randomNonce: locklift.utils.getRandomNonce()
        },
        keyPair,
    }, locklift.utils.convertCrystal(5, 'nano'));

    user.setKeyPair(keyPair);
    spinner.stop();

    await logContract(user);

    spinner.start('Deploying factory');
    const factory = await locklift.giver.deployContract({
        contract: BoosterFactory,
        constructorParams: {
            _owner: user.address,
            _managers: [
                '0x5a486a7550514dc5006dbf25937cdccbed5476867c93811b1376d602aa28d1d0',
                '0x1757c06652bdcfb066a90b65832b58090236b5314b4cb7458e1e60ca44f16dbb'
            ],
            _rewarder: rewarder.address,
            _ping_token_root: response.ping_token,
            _account_platform: BoosterAccountPlatform.code,
            _account_implementation: '',
            _passport_platform: BoosterPassportPlatform.code,
            _passport_implementation: ''
        },
    }, locklift.utils.convertCrystal(response.factory_value, 'nano'));
    spinner.stop();

    await logContract(factory);

    spinner.start('Setting up account code');
    await user.runTarget({
        contract: factory,
        method: 'upgradeAccountCode',
        params: {
            _account_implementation: BoosterAccount.code
        },
        value: locklift.utils.convertCrystal(1, 'nano')
    });
    spinner.stop();

    spinner.start('Setting up passport code');
    await user.runTarget({
        contract: factory,
        method: 'upgradePassportCode',
        params: {
            _passport_implementation: BoosterPassport.code
        },
        value: locklift.utils.convertCrystal(1, 'nano')
    });
    spinner.stop();

    if (response.add_farming_pools) {
        // Adding farmings
        const dex_pair_USDT_USDC = '0:b3b454752cf29575ba0f79cd6ee7fb5ed5fe2ad06555e28c12f7ee88835d728f';
        const dex_pair_WEVER_USDT = '0:771e3d124c7a824d341484718fcf1af03dd4ba1baf280adeb0663bb030ce2bf9';
        const dex_pair_QUBE_WEVER = '0:c8021e99e5329cd863ed206e2729be28586dc2ab398ed4d5f2bbddf2f44d8b01';

        const USDT = '0:a519f99bb5d6d51ef958ed24d337ad75a1c770885dcd42d51d6663f9fcdacfb2';
        const USDC = '0:c37b3fafca5bf7d3704b081fde7df54f298736ee059bf6d32fac25f5e6085bf6';
        const QUBE = '0:9f20666ce123602fd7a995508aeaa0ece4f92133503c0dfbd609b3239f3901e2';
        const WEVER = '0:a49cd4e158a9a15555e624759e2e4e766d22600b7800d891e46f9291f044a93d';


        spinner.start('Adding QUBE/WEVER farming');
        await user.runTarget({
            contract: factory,
            method: 'addFarming',
            params: {
                farming_pool: "0:f96da52e928cf4d8e54dcec0e7f7fefddfb7592590f05705dcaa9f211102fbc5",
                lp: "0:0bf177d4dcc468293502ce81fd9a05285f7621814a705a000020dc15fa8258f8",
                pair: dex_pair_QUBE_WEVER,
                left: QUBE,
                right: WEVER,
                rewards: [QUBE],
                swaps: {},
                rewarder: rewarder.address,
                reward_fee: 10,
                lp_fee: 10,
                ping_value: locklift.utils.convertCrystal(2, 'nano')
            },
            value: locklift.utils.convertCrystal(1, 'nano')
        });
        spinner.stop();

        spinner.start('Adding USDT/USDC farming');

        await user.runTarget({
            contract: factory,
            method: 'addFarming',
            params: {
                farming_pool: "0:60efb0dbae8fddadb844d3e5a2d6ece2739d0fe38dd5b4ce7f60f53a2d2b676f",
                lp: "0:1ddd1a0a7d6ee3cef8ccb9e6aa02f5c142658522ddd40f21ae7160177ced0e12",
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
                rewarder: rewarder.address,
                reward_fee: 5,
                lp_fee: 5,
                ping_value: locklift.utils.convertCrystal(2, 'nano')
            },
            value: locklift.utils.convertCrystal(1, 'nano')
        });
        spinner.stop();
    }

    spinner.start('Transferring factory ownership');
    await user.runTarget({
        contract: factory,
        method: 'transferOwnership',
        params: {
            newOwner: response.owner,
        },
        value: locklift.utils.convertCrystal(1, 'nano')
    });
    spinner.stop();
};


main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
