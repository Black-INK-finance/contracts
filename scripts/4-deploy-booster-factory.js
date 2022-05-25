const logger = require('mocha-logger');
const prompts = require('prompts');
const { isValidTonAddress } = require('../test/utils');


const main = async () => {
    const response = await prompts([
        {
            type: 'text',
            name: 'owner',
            message: 'Fabric owner',
            validate: value => isValidTonAddress(value) ? true : 'Invalid address'
        },
        {
            type: 'text',
            name: 'manager',
            message: 'Booster manager (pings booster accounts)',
            validate: value => isValidTonAddress(value) ? true : 'Invalid address'
        }
    ]);

    const BoosterFactory = await locklift.factory.getContract('BoosterFactory');
    const BoosterAccount = await locklift.factory.getContract('BoosterAccount');
    const BoosterAccountPlatform = await locklift.factory.getContract('BoosterAccountPlatform');

    const factory = await locklift.giver.deployContract({
        contract: BoosterFactory,
        constructorParams: {
            _owner: response.owner,
            _manager: response.manager,
            _account: BoosterAccount.code,
            _account_platform: BoosterAccountPlatform.code
        }
    });

    logger.log(`Booster factory: ${factory.address}`);
};


main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
