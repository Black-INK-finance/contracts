const logger = require('mocha-logger');
const prompts = require('prompts');
const ora = require('ora');
const { isValidTonAddress, logContract } = require('../../test/utils');
const BigNumber = require("bignumber.js");


const USDT = '0:a519f99bb5d6d51ef958ed24d337ad75a1c770885dcd42d51d6663f9fcdacfb2';
const USDC = '0:c37b3fafca5bf7d3704b081fde7df54f298736ee059bf6d32fac25f5e6085bf6';
const QUBE = '0:9f20666ce123602fd7a995508aeaa0ece4f92133503c0dfbd609b3239f3901e2';
const WEVER = '0:a49cd4e158a9a15555e624759e2e4e766d22600b7800d891e46f9291f044a93d';
const DUSA = '0:b3ed4b9402881c7638566b410dda055344679b065dce19807497c62202ba9ce3';
const BRIDGE = '0:f2679d80b682974e065e03bf42bbee285ce7c587eb153b41d761ebfd954c45e1';
const WBTC = '0:2ba32b75870d572e255809b7b423f30f36dd5dea075bd5f026863fceb81f2bcf';
const WETH = '0:59b6b64ac6798aacf385ae9910008a525a84fc6dcf9f942ae81f8e8485fe160d';
const DAI = '0:eb2ccad2020d9af9cec137d3146dde067039965c13a27d97293c931dae22b2b9';


// Farmings
const farmings = {
    'USDT_USDC': {
        lp: '0:1ddd1a0a7d6ee3cef8ccb9e6aa02f5c142658522ddd40f21ae7160177ced0e12',
        pair: '0:b3b454752cf29575ba0f79cd6ee7fb5ed5fe2ad06555e28c12f7ee88835d728f',
        pool: '0:60efb0dbae8fddadb844d3e5a2d6ece2739d0fe38dd5b4ce7f60f53a2d2b676f',
    },
    'WEVER_BRIDGE': {
        lp: '0:5c66f770d439212181bb6f62714bc235f754653ad9e2aca5a685ff7979174ea2',
        pair: '0:83b88abbcd562c8d8dc4cab30ec1ded86a4ded99000ca02425715e5cec754f06',
        pool: '0:39c1ba1305438e59c444267f8887d3ceb7312ab906760b8b891c865217ea8ff0',
    },
    'WEVER_USDT': {
        lp: '0:c4faf70154a6d885bdc5856df54b9a3507eb4a98681e9902fdefc369bbb9d7b9',
        pair: '0:771e3d124c7a824d341484718fcf1af03dd4ba1baf280adeb0663bb030ce2bf9',
        pool: '0:8fdbe762b12899458591789da5ff6c241d6bdbab1219c0757ec81b30f05a268d',
    },
    'QUBE_WEVER': {
        lp: '0:0bf177d4dcc468293502ce81fd9a05285f7621814a705a000020dc15fa8258f8',
        pair: '0:c8021e99e5329cd863ed206e2729be28586dc2ab398ed4d5f2bbddf2f44d8b01',
        pool: '0:f96da52e928cf4d8e54dcec0e7f7fefddfb7592590f05705dcaa9f211102fbc5',
    },
    'WBTC_WEVER': {
        lp: '0:a84a6e0f862f0576803df3c5864cef4ba18b81c908fc8425bace5c4397b252cb',
        pair: '0:ff0cc18a9e2bb4f7121e4a878d8721618b26070c96888e6849768d1dd7b99c21',
        pool: '0:d3ef09f169ee408eaf5da0beaf0a893455afb2cf785f24ca70aea4cf2ab14a1a',
    },
    'QUBE_BRIDGE': {
        lp: '0:cbb299c2a80b4976bcdd2d4842c66a2a5637c12fee2af3312c299987d9ae0a71',
        pair: '0:8be972dfd026769d3904d64a3cd929f6e1c7f6b79af6c3bebe320ade5c0b7e82',
        pool: '0:4cc84ba606733383293bdde9469c0a84479f110f8029f79222893e2d2e5db335',
    },
    'WETH_WEVER': {
        lp: '0:4edbbeea7edae19059a1a1ef92491dbf0533e25f90c68825f3563530e932b1f5',
        pair: '0:b80dd89fb3fe902ba9536f5e1f9240397feaec1d2edc28307228d3e71f71936e',
        pool: '0:18d181e45c8f02c9bd62d9f255904ff71b8d536cae7d6bb92dcad6da283a917a',
    },
    'WBTC_BRIDGE': {
        lp: '0:bfd8c710207e6e5918912317e402eea90feada9da5ee17146d1bc5887b4a8d8f',
        pair: '0:ab39f6f37b9eb96f187199ff7f88745efe99bfa7624691f9f7d1e7713b6bc478',
        pool: '0:a90b6b0c30053cf23ce3c86658a666b3c87e20cc3e7698921ccc53fcfe776ca9',
    },
    'WEVER_DAI': {
        lp: '0:24a08cec5a40582010000295338d1a1f5b01ea8934ed9e2ec861b9d4a3b22519',
        pair: '0:f0120fdea2a4e1977f627caae480b8ba9afa4d76296a014050e8a584f710ff06',
        pool: '0:191242aebc8aaebb60c59cd873adea64dd4e6a7b73bfafc56626794ea7f5e5df',
    },
    'WEVER_USDC': {
        lp: '0:69d2ef451ffe62118d13ded98894a202add48db891202a25db543b6d4d9f09a1',
        pair: '0:d6b8696c46abe5074f3eccb11d2371e07abd4ac6202cce04e9d903e361ee834b',
        pool: '0:71bc06c32436236c1979fc622ab431297c2863e0561cb58e03b09499ada8f6b8',
    },
    'WEVER_DUSA': {
        lp: '0:36af9d44defe010defa71d53b2986d82bac935edfb29a831076c657bbd9b804e',
        pair: '0:e4bcb973497707dad7a2129361941cfafe3391f6ac40dda7cf2ca29c2d6ceabd',
        pool: '0:2147e2dc27660d8bf9311974ed14ac936cb8be2520330f1d0c87590db466809c',
    },
    'USDT_DUSA': {
        lp: '0:f857595f870db90bb2bb2f35e59e0375abc49797d8b0298efb34d19fcd0da3c6',
        pair: '0:a2d80cc6a64eda8bb718b775fa592ad2cf4cb4d977d19669a943f9d996d9d6e6',
        pool: '0:2ff5db6e886e337c921154f3de9b77cfcadd1940c84b4f3b97c312c069cd7ea0',
    },
};

const vault = "0:6fa537fa97adf43db0206b5bec98eb43474a9836c016a190ac8b792feb852230";

const lp_fee = 8;
const reward_fee = 16;

const ping_value = locklift.utils.convertCrystal(2, 'nano');


const main = async () => {
    logger.log('Dont forget to check default values in the following contracts!!');
    logger.log('contracts/booster/Gas.sol');
    logger.log('contracts/booster/Constants.sol');

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
    }, locklift.utils.convertCrystal(10, 'nano'));

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
                '0x1757c06652bdcfb066a90b65832b58090236b5314b4cb7458e1e60ca44f16dbb',
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

    // Adding farmings
    if (response.add_farming_pools) {
        spinner.start('Adding USDT/USDC farming');
        await user.runTarget({
            contract: factory,
            method: 'addFarming',
            params: {
                vault,
                farming_pool: farmings.USDT_USDC.pool,
                lp: farmings.USDT_USDC.lp,
                pair: farmings.USDT_USDC.pair,
                left: USDT,
                right: USDC,
                rewards: [WEVER, QUBE],
                swaps: {
                    [QUBE]: {
                        token: WEVER,
                        pairType: 0,
                        pair: farmings.QUBE_WEVER.pair
                    },
                    [WEVER]: {
                        token: USDT,
                        pairType: 0,
                        pair: farmings.WEVER_USDT.pair
                    }
                },
                rewarder: rewarder.address,
                reward_fee,
                lp_fee,
                ping_value
            },
            value: locklift.utils.convertCrystal(1, 'nano')
        });
        spinner.stop();

        spinner.start('Adding WEVER/BRIDGE farming');
        await user.runTarget({
            contract: factory,
            method: 'addFarming',
            params: {
                vault,
                farming_pool: farmings.WEVER_BRIDGE.pool,
                lp: farmings.WEVER_BRIDGE.lp,
                pair: farmings.WEVER_BRIDGE.pair,
                left: WEVER,
                right: BRIDGE,
                rewards: [QUBE, BRIDGE],
                swaps: {
                    [QUBE]: {
                        token: WEVER,
                        pairType: 0,
                        pair: farmings.QUBE_WEVER.pair
                    }
                },
                rewarder: rewarder.address,
                reward_fee,
                lp_fee,
                ping_value
            },
            value: locklift.utils.convertCrystal(1, 'nano')
        });
        spinner.stop();

        spinner.start('Adding WEVER/USDT farming');
        await user.runTarget({
            contract: factory,
            method: 'addFarming',
            params: {
                vault,
                farming_pool: farmings.WEVER_USDT.pool,
                lp: farmings.WEVER_USDT.lp,
                pair: farmings.WEVER_USDT.pair,
                left: WEVER,
                right: USDT,
                rewards: [QUBE, WEVER],
                swaps: {
                    [QUBE]: {
                        token: WEVER,
                        pairType: 0,
                        pair: farmings.QUBE_WEVER.pair
                    }
                },
                rewarder: rewarder.address,
                reward_fee,
                lp_fee,
                ping_value
            },
            value: locklift.utils.convertCrystal(1, 'nano')
        });
        spinner.stop();

        spinner.start('Adding QUBE/WEVER farming');
        await user.runTarget({
            contract: factory,
            method: 'addFarming',
            params: {
                vault,
                farming_pool: farmings.QUBE_WEVER.pool,
                lp: farmings.QUBE_WEVER.lp,
                pair: farmings.QUBE_WEVER.pair,
                left: QUBE,
                right: WEVER,
                rewards: [QUBE],
                swaps: {},
                rewarder: rewarder.address,
                reward_fee,
                lp_fee,
                ping_value
            },
            value: locklift.utils.convertCrystal(1, 'nano')
        });
        spinner.stop();

        spinner.start('Adding WBTC/WEVER farming');
        await user.runTarget({
            contract: factory,
            method: 'addFarming',
            params: {
                vault,
                farming_pool: farmings.WBTC_WEVER.pool,
                lp: farmings.WBTC_WEVER.lp,
                pair: farmings.WBTC_WEVER.pair,
                left: WBTC,
                right: WEVER,
                rewards: [QUBE, WEVER],
                swaps: {
                    [QUBE]: {
                        token: WEVER,
                        pairType: 0,
                        pair: farmings.QUBE_WEVER.pair
                    }
                },
                rewarder: rewarder.address,
                reward_fee,
                lp_fee,
                ping_value
            },
            value: locklift.utils.convertCrystal(1, 'nano')
        });
        spinner.stop();

        spinner.start('Adding QUBE/BRIDGE farming');
        await user.runTarget({
            contract: factory,
            method: 'addFarming',
            params: {
                vault,
                farming_pool: farmings.QUBE_BRIDGE.pool,
                lp: farmings.QUBE_BRIDGE.lp,
                pair: farmings.QUBE_BRIDGE.pair,
                left: QUBE,
                right: BRIDGE,
                rewards: [QUBE, BRIDGE],
                swaps: {},
                rewarder: rewarder.address,
                reward_fee,
                lp_fee,
                ping_value
            },
            value: locklift.utils.convertCrystal(1, 'nano')
        });
        spinner.stop();

        spinner.start('Adding WETH/WEVER farming');
        await user.runTarget({
            contract: factory,
            method: 'addFarming',
            params: {
                vault,
                farming_pool: farmings.WETH_WEVER.pool,
                lp: farmings.WETH_WEVER.lp,
                pair: farmings.WETH_WEVER.pair,
                left: WETH,
                right: WEVER,
                rewards: [QUBE, WEVER],
                swaps: {
                    [QUBE]: {
                        token: WEVER,
                        pairType: 0,
                        pair: farmings.QUBE_WEVER.pair
                    }
                },
                rewarder: rewarder.address,
                reward_fee,
                lp_fee,
                ping_value
            },
            value: locklift.utils.convertCrystal(1, 'nano')
        });
        spinner.stop();

        spinner.start('Adding WBTC/BRIDGE farming');
        await user.runTarget({
            contract: factory,
            method: 'addFarming',
            params: {
                vault,
                farming_pool: farmings.WBTC_BRIDGE.pool,
                lp: farmings.WBTC_BRIDGE.lp,
                pair: farmings.WBTC_BRIDGE.pair,
                left: WBTC,
                right: BRIDGE,
                rewards: [QUBE, BRIDGE],
                swaps: {
                    [QUBE]: {
                        token: BRIDGE,
                        pairType: 0,
                        pair: farmings.QUBE_BRIDGE.pair
                    },
                },
                rewarder: rewarder.address,
                reward_fee,
                lp_fee,
                ping_value
            },
            value: locklift.utils.convertCrystal(1, 'nano')
        });
        spinner.stop();

        spinner.start('Adding WEVER/DAI farming');
        await user.runTarget({
            contract: factory,
            method: 'addFarming',
            params: {
                vault,
                farming_pool: farmings.WEVER_DAI.pool,
                lp: farmings.WEVER_DAI.lp,
                pair: farmings.WEVER_DAI.pair,
                left: WEVER,
                right: DAI,
                rewards: [QUBE, WEVER],
                swaps: {
                    [QUBE]: {
                        token: WEVER,
                        pairType: 0,
                        pair: farmings.QUBE_WEVER.pair
                    },
                },
                rewarder: rewarder.address,
                reward_fee,
                lp_fee,
                ping_value
            },
            value: locklift.utils.convertCrystal(1, 'nano')
        });
        spinner.stop();

        spinner.start('Adding WEVER/USDC farming');
        await user.runTarget({
            contract: factory,
            method: 'addFarming',
            params: {
                vault,
                farming_pool: farmings.WEVER_USDC.pool,
                lp: farmings.WEVER_USDC.lp,
                pair: farmings.WEVER_USDC.pair,
                left: WEVER,
                right: USDC,
                rewards: [QUBE, WEVER],
                swaps: {
                    [QUBE]: {
                        token: WEVER,
                        pairType: 0,
                        pair: farmings.QUBE_WEVER.pair
                    },
                },
                rewarder: rewarder.address,
                reward_fee,
                lp_fee,
                ping_value
            },
            value: locklift.utils.convertCrystal(1, 'nano')
        });
        spinner.stop();

        spinner.start('Adding WEVER/DUSA farming');
        await user.runTarget({
            contract: factory,
            method: 'addFarming',
            params: {
                vault,
                farming_pool: farmings.WEVER_DUSA.pool,
                lp: farmings.WEVER_DUSA.lp,
                pair: farmings.WEVER_DUSA.pair,
                left: WEVER,
                right: DUSA,
                rewards: [DUSA],
                swaps: {},
                rewarder: rewarder.address,
                reward_fee,
                lp_fee,
                ping_value
            },
            value: locklift.utils.convertCrystal(1, 'nano')
        });
        spinner.stop();

        spinner.start('Adding USDT/DUSA farming');
        await user.runTarget({
            contract: factory,
            method: 'addFarming',
            params: {
                vault,
                farming_pool: farmings.USDT_DUSA.pool,
                lp: farmings.USDT_DUSA.lp,
                pair: farmings.USDT_DUSA.pair,
                left: USDT,
                right: DUSA,
                rewards: [DUSA],
                swaps: {},
                rewarder: rewarder.address,
                reward_fee,
                lp_fee,
                ping_value
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
