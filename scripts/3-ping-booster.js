const booster_factory_address = process.env.BOOSTER_FACTORY;
const booster_admin_address = process.env.BOOSTER_ADMIN;
const ping_delay_seconds = process.env.PING_DELAY_SECONDS;
const booster_account_min_balance = process.env.BOOSTER_ACCOUNT_MIN_BALANCE;


const main = async () => {
    // Initialize booster factory
    const booster_factory = await locklift.factory.getContract('BoosterFactory');
    booster_factory.setAddress(booster_factory_address);

    // Initialize booster admin
    const booster_admin = await locklift.factory.getContract('BoosterAdmin');
    booster_admin.setAddress(booster_admin_address);

    // Get all booster accounts by code hash
    const booster_account_code_hash = await booster_factory.call({
        method: 'getAccountPlatformHash'
    });

    // Filter out booster accounts
    // - Only initialized
    // - Only ready to be pinged
    // - Only non-recently pinged

    // Ping all of them
    // - Split accounts in chunks, 100 accounts each
    const chunks = [];

    // - Ping each chunk
    for (const chunk of chunks) {

    }
};


main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
