pragma ton-solidity ^0.57.1;


library Constants {
    uint128 constant BPS = 100;

    // - Restrictions
    uint128 constant MAX_FEE = 50;

    uint constant MIN_PING_FREQUENCY = 60 * 15; // 15 minutes
    uint constant PING_DURATION = 5 * 60; // 5 minutes
    uint constant PINGS_PER_SKIM = 10; // Skim fees every 10th ping

    // -- Farming Nonce
    uint32 constant REINVEST_REQUIRED = 11;
    uint32 constant NO_REINVEST_REQUIRED = 22;
}
