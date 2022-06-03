const booster_factory_address = process.env.BOOSTER_FACTORY;
const manager_address = process.env.MANAGER;
const ping_delay_seconds = process.env.PING_DELAY_SECONDS;
const booster_account_min_balance = process.env.BOOSTER_ACCOUNT_MIN_BALANCE;


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

    // Filter out booster accounts which are not "ready-to-be-pinged"

    // Ping all of them
    // - Split accounts in chunks, 100 accounts each
    const chunks = [];

    // - Ping each chunk
    for (const chunk of chunks) {
        await manager.run({

        });
    }
};


main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
