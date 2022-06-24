pragma ton-solidity ^0.57.1;


library Constants {
    uint128 constant BPS = 100;

    // Max value in BPS for (LP fee + rewards fee)
    uint128 constant MAX_FEE = 50;

    uint128 constant MIN_SLIPPAGE = 10;

    // - Prod
    // uint constant MIN_PING_FREQUENCY = 60 * 15; // 15 minutes
    // - Test
    uint64 constant MIN_PING_FREQUENCY = 10; // 10 seconds

    // How often to skim LP & rewards fees from account
    uint64 constant PINGS_PER_SKIM = 3; // Skim fees every 10th ping

    // -- Farming Nonce
    uint32 constant REINVEST_REQUIRED = 11;
    uint32 constant NO_REINVEST_REQUIRED = 22;
}
