pragma ton-solidity ^0.57.1;


library Utils {
    uint128 constant BPS  = 100;

    // Constant gas values
    uint128 constant DEPLOY_TOKEN_WALLET = 0.2 ton;

    uint128 constant BOOSTER_UPGRADE_ACCOUNT = 0.5 ton;
    uint128 constant BOOSTER_DEPLOY_ACCOUNT = 10 ton;
    uint128 constant BOOSTER_CASHBACK_MANAGER_EXTRA = 0.03 ton;

    // - Booster-farming interactions
    uint128 constant FARMING_CLAIM_REWARD = 8 ton;
    uint128 constant FARMING_REQUEST_USER_DATA = 1 ton;
    uint128 constant FARMING_WITHDRAW_LP = 5 ton;
    uint128 constant FARMING_DEPOSIT_LP = 5 ton;
    uint128 constant FARMING_SKIM_FEES = 0.5 ton;

    uint32 constant REINVEST_REQUIRED = 11;
    uint32 constant NO_REINVEST_REQUIRED = 22;

// - Booster-dex interactions
    uint128 constant DEX_DEPOSIT_LIQUIDITY = 5 ton;
    uint128 constant DEX_SWAP = 5 ton;

    // - Restrictions
    uint128 constant MAX_FEE = 50;
    uint constant MIN_PING_FREQUENCY = 60 * 15; // 15 minutes

    // Errors
}
