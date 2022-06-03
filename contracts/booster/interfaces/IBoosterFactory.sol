pragma ton-solidity ^0.57.1;

import "./IBoosterBase.sol";


interface IBoosterFactory is IBoosterBase {
    function withdrawPingTokens(
        uint128 amount
    ) external;

    function deriveAccount(
        address _owner,
        address farming_pool
    ) external responsible returns(address);

    function deployAccount(
        address _owner,
        address farming_pool
    ) external;

    function setRecommendedPriceLimit(
        uint128 limit
    ) external;

    function upgradeAccountCode(TvmCell _account) external;
    function upgradeAccounts(address[] accounts) external;

    function upgrade(
        TvmCell code
    ) external;

    function getAccountPlatformCodeHash() external returns(uint);
    function encodePingTopUp(
        address account
    ) external pure returns(TvmCell);

    function addFarming(
        address farming_pool,
        address lp,
        address pair,
        address left,
        address right,
        address[] rewards,
        mapping (address => SwapDirection) swaps,
        uint recommended_ping_frequency,
        address rewarder,
        uint128 reward_fee,
        uint128 lp_fee
    ) external;

    function setFarmingPaused(
        address farming_pool,
        bool paused
    ) external;

    function getDetails() external returns (
        uint _version,
        address _manager,
        address _rewarder,
        address _ping_token_root,
        address _ping_token_wallet,
        uint128 _recommended_ping_price_limit,
        mapping (address => FarmingPoolSettings) _farmings,
        TvmCell _account_platform,
        TvmCell _account,
        uint _account_version
    );

    function receiveTokenWallet(
        address wallet
    ) external;
}
