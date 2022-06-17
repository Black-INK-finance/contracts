const _ = require('underscore');
const logger = require('mocha-logger');
const BigNumber = require("bignumber.js");


const main = async () => {
    // Initialize booster factory
    const booster_factory = await locklift.factory.getContract('BoosterFactory');
    booster_factory.setAddress('0:81ca282730d343e570a9808b5769bbaf6c1e8b00f65c294f926beb1a894ae1c9');

    const [manager_key] = await locklift.keys.getKeyPairs();

    logger.log(`Manager public key: 0x${manager_key.public}`);

    // Get all booster accounts from events
    const events = await booster_factory.getEvents('AccountDeployed');

    const accounts = events.map(e => e.value.account);

    // Get ping price in PING tokens
    const ping_price = 0;

    logger.log(`Ping price: ${ping_price}`);

    for (const account of accounts) {
        logger.success("-".repeat(100));
        logger.log(`Working on account ${account}`);

        const booster_account = await locklift.factory.getContract('BoosterAccount_V1');
        booster_account.setAddress(account);

        // Check account initialized
        const is_initialized = await booster_account.call({ method: 'isInitialized' });

        if (is_initialized === false) {
            logger.log(`Booster not initialized, quit ping`);
            continue;
        } else {
            logger.log(`Booster account initialized`);
        }

        // Get account passport
        const passport_address = await booster_account.call({ method: 'passport' });
        const passport = await locklift.factory.getContract('BoosterPassport');
        passport.setAddress(passport_address);

        logger.log(`Booster passport: ${passport_address}`);

        const passport_details = await passport.call({ method: 'getDetails' });

        // Check auto ping enabled
        if (passport_details._accounts[account].auto_ping_enabled === false) {
            logger.log(`Auto ping disabled, quit ping`);
            continue;
        } else {
            logger.log(`Auto ping enabled`);
        }

        // Check balance is enough
        if (passport_details._ping_balance.isLessThan(ping_price)) {
            logger.log(`Ping balance too low, quit ping`);
            continue;
        } else {
            logger.log(`Ping balance is sufficient`);
        }

        // Check it's not too early to ping
        const last_ping = new BigNumber(passport_details._accounts[account].last_ping);
        const ping_frequency = new BigNumber(passport_details._accounts[account].ping_frequency);
        const now = new BigNumber(+ new Date()).div(1000);

        // TODO: check account has at least some tokens

        if (last_ping.plus(ping_frequency).isGreaterThanOrEqualTo(now)) {
            logger.log(`Last ping was recently, quit ping`);
            continue;
        } else {
            logger.log(`The time has come, sending ping`);
        }

        await passport.run({
            method: 'pingByManager',
            params: {
                price: ping_price,
                account,
                counter: passport_details._accounts[account].ping_counter
            },
            keyPair: manager_key
        })
            .then(tx => logger.log(`Ping tx: ${tx.transaction.id}`))
            .catch(e => logger.error(`Ping failed: ${e.message}`));
    }
};


main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
