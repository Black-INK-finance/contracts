pragma ton-solidity ^0.57.1;


library Gas {
    uint128 constant UPGRADE_ACCOUNT = 0.5 ton;
    uint128 constant DEPLOY_BOOSTER_ACCOUNT = 100 ton;

    uint128 constant DEPLOY_TOKEN_WALLET = 0.2 ton;

    uint128 constant FARMING_CLAIM_REWARD = 8 ton;
    uint128 constant FARMING_REQUEST_USER_DATA = 1 ton;
    uint128 constant FARMING_WITHDRAW_LP = 5 ton;
    uint128 constant FARMING_DEPOSIT_LP = 5 ton;

    uint128 constant DEX_DEPOSIT_LIQUIDITY = 5 ton;
    uint128 constant DEX_SWAP = 5 ton;
}
