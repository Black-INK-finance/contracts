const main = async () => {
    // Get all booster accounts by code hash
    // Check they are initialized
    // Ping all of them
};


main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
