pragma ton-solidity ^0.57.1;


library Gas {
    // Common gas values
    uint128 constant DEPLOY_TOKEN_WALLET = 0.2 ton;

    uint128 constant BOOSTER_PASSPORT_TARGET_BALANCE = 5 ton;
    uint128 constant BOOSTER_ACCOUNT_TARGET_BALANCE = 15 ton;

    // Booster factory
    uint128 constant BOOSTER_FACTORY_ACCOUNT_SKIM = 3 ton;
    uint128 constant BOOSTER_FACTORY_ACCOUNT_UPDATE = 0.5 ton;
    uint128 constant BOOSTER_FACTORY_PASSPORT_UPDATE = 0.5 ton;
    uint128 constant BOOSTER_FACTORY_ACCOUNT_UPGRADE = 1 ton;
    uint128 constant BOOSTER_FACTORY_PASSPORT_UPGRADE = 1 ton;
    uint128 constant BOOSTER_FACTORY_MIN_PING_VALUE = 1 ton;

    uint128 constant BOOSTER_UPGRADE_ACCOUNT = 0.5 ton;
    uint128 constant BOOSTER_DEPLOY_ACCOUNT = 1 ton;
    uint128 constant BOOSTER_DEPLOY_PASSPORT = 1 ton;
    uint128 constant BOOSTER_FACTORY_THROW_PING_TOKENS = 1 ton;

    // - Booster-farming interactions
    uint128 constant FARMING_CLAIM_REWARD = 10 ton;
    uint128 constant FARMING_REQUEST_USER_DATA = 1 ton;
    uint128 constant FARMING_WITHDRAW_LP = 5 ton;

    uint128 constant BOOSTER_ACCOUNT_REQUEST_DEX_PAIR_BALANCES = 0.3 ton;
    uint128 constant BOOSTER_ACCOUNT_DEPOSIT_LP_TO_FARMING = 5 ton;
    uint128 constant BOOSTER_ACCOUNT_DEX_SWAP = 5 ton;
    uint128 constant BOOSTER_ACCOUNT_DEPOSIT_TOKEN_TO_DEX = 5 ton;
    uint128 constant BOOSTER_ACCOUNT_TRANSFER_FEES = 0.5 ton;

    // Booster keeper attach exceeding gas to every ping
    // Once the balance is over than the BOOSTER_ACCOUNT_TARGET_BALANCE more than this value
    // it will be sent back to the factory
    uint128 constant BOOSTER_ACCOUNT_EXCEEDING_GAS_LIMIT = 3 ton;

    // Passport pays itself for keeper external in calls, so it's balance decreases
    // Once the balance is less than the BOOSTER_PASSPORT_TARGET_BALANCE more than this value
    // Factory will top up the passport balance
    uint128 constant BOOSTER_PASSPORT_SPENT_GAS_LIMIT = 2 ton;

    uint128 constant BOOSTER_BUYBACK_DEX_SWAP = 5 ton;

    uint128 constant BOOSTER_ACCOUNT_CYCLE_COST = 3 ton;
}
