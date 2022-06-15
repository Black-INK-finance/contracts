const logger = require('mocha-logger');
const prompts = require('prompts');
const ora = require('ora');
const { isValidTonAddress, logContract } = require('../../test/utils');
const BigNumber = require("bignumber.js");


const main = async () => {
    logger.log('Dont forget to check default values in the following contracts!!');
    logger.log('contracts/Gas.sol');
    logger.log('contracts/Constants.sol');

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

    spinner.start('Deploying factory');
    const factory = await locklift.giver.deployContract({
        contract: BoosterFactory,
        constructorParams: {
            _owner: response.owner,
            _managers: [response.manager_public_key],
            _rewarder: rewarder.address,
            _ping_token_root: response.ping_token,
            _account_platform: BoosterAccountPlatform.code,
            _account_implementation: BoosterAccount.code,
            _passport_platform: BoosterPassportPlatform.code,
            _passport_implementation: BoosterPassport.code
        },
    }, locklift.utils.convertCrystal(response.factory_value, 'nano'));
    spinner.stop();

    await logContract(factory);
};


main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
