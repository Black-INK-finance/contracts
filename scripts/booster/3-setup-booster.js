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
            name: 'manager_public_key',
            message: 'Manager public key',
        },
        {
            type: 'text',
            name: 'ping_token',
            message: 'Project token root (keeper rewards, buybacks, etc)',
            validate: value => isValidTonAddress(value) ? true : 'Invalid address',
        },
        {
            type: 'number',
            name: 'ping_price_limit',
            message: 'Ping price limit in decimals (default value)',
        }
    ]);

    const BoosterFactory = await locklift.factory.getContract('BoosterFactory');
    const BoosterManager = await locklift.factory.getContract('BoosterManager');
    const BoosterBuyBack = await locklift.factory.getContract('BoosterBuyBack');
    const BoosterAccount = await locklift.factory.getContract('BoosterAccount_V1');
    const BoosterAccountPlatform = await locklift.factory.getContract('BoosterAccountPlatform');


    const spinner = ora('Deploying booster manager').start();
    const manager = await locklift.giver.deployContract({
        contract: BoosterManager,
        constructorParams: {
            _owner: response.manager_public_key,
            _internalOwner: response.owner
        }
    }, locklift.utils.convertCrystal(100, 'nano'));
    manager.name = 'Manager';
    spinner.stop();

    await logContract(manager);

    spinner.start('Deploying rewarder');
    const rewarder = await locklift.giver.deployContract({
        contract: BoosterBuyBack,
        constructorParams: {
            _owner: response.owner
        }
    }, locklift.utils.convertCrystal(100, 'nano'));
    rewarder.name = 'Rewarder (BuyBack)';
    spinner.stop();

    await logContract(rewarder);

    spinner.start('Deploying factory');
    const factory = await locklift.giver.deployContract({
        contract: BoosterFactory,
        constructorParams: {
            _owner: response.owner,
            _manager: manager.address,
            _rewarder: rewarder.address,
            _ping_token_root: response.ping_token,
            _recommended_ping_price_limit: response.ping_price_limit,
            _account_platform: BoosterAccountPlatform.code,
            _account: BoosterAccount.code
        },
    });
    spinner.stop();

    await logContract(factory);
};


main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
