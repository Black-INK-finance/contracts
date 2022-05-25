pragma ton-solidity ^0.57.1;

import "./IBoosterBase.sol";


interface IBoosterFactory is IBoosterBase {
    function deriveAccount(
        address _owner,
        address farming_pool
    ) external responsible returns(address);

    function deployAccount(address farming_pool) external;
    function upgradeAccountCode(TvmCell _account) external;
    function upgradeAccounts(address[] accounts) external;

    function upgrade(
        TvmCell code
    ) external;

    function getAccountPlatformCodeHash() external returns(uint);

    function addFarming(
        address dex,
        address farming_pool,
        address lp,
        address pair,
        address left,
        address right,
        address[] rewards,
        mapping (address => SwapDirection) swaps,
        address rewarder,
        uint128 fee
    ) external;

    function setFarmingPaused(
        address farming_pool,
        bool paused
    ) external;

    function getDetails() external returns (
        uint _version,
        address _manager,
        mapping (address => FarmingPoolSettings) _farmings,
        TvmCell _account_platform,
        TvmCell _account,
        uint _account_version
    );
}
