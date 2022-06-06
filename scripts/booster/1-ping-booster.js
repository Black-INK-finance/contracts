const _ = require('underscore');
const logger = require('mocha-logger');


const booster_factory_address = process.env.BOOSTER_FACTORY;
const manager_address = process.env.MANAGER;


const main = async () => {
    // Initialize booster factory
    const booster_factory = await locklift.factory.getContract('BoosterFactory');
    booster_factory.setAddress(booster_factory_address);

    // Initialize booster manager
    const manager = await locklift.factory.getContract('Manager');
    manager.setAddress(manager_address);

    const [keyPair] = await locklift.keys.getKeyPairs();
    manager.setKeyPair(keyPair);

    // Get all booster accounts by code hash
    const booster_account_code_hash = await booster_factory.call({
        method: 'getAccountPlatformHash'
    });

    // Get ping price in PING tokens
    const ping_price = 0;

    // Filter out booster accounts which are not "ready-to-be-pinged"
    const accounts = [];

    // Ping all of them
    // - Split accounts in chunks, 100 accounts each
    const chunks = _.chunk(accounts, 100);

    // - Ping each chunk
    for (const [i, chunk] of chunks.entries()) {
        const tx = await manager.run({
            method: 'ping',
            params: {
                pings: chunk.map(a => Object({
                    account: a,
                    price: ping_price,
                    skim: true
                }))
            }
        });

        logger.log(`Ping ${i}, ${chunk.length} accounts tx: ${tx.transaction.id}`);
    }
};


main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
