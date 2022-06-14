pragma ton-solidity ^0.57.1;

import "./IBoosterBase.sol";


interface IBoosterFactory is IBoosterBase {
    function pingAccount(
        address _owner,
        uint counter,
        address account,
        uint128 price,
        uint128 required_top_up
    ) external;

    function deriveAccount(
        address _owner,
        address farming_pool
    ) external responsible returns(address);

    function derivePassport(
        address _owner
    ) external responsible returns(address);

    function withdrawPingTokens(
        address _owner,
        uint128 amount,
        address remainingGasTo
    ) external;

    function claimSpentPingTokens() external;

    function deployAccount(
        address farming_pool,
        uint128 ping_frequency,
        uint128 max_ping_price,
        bool deploy_passport
    ) external;

    function upgradeAccountCode(TvmCell code) external;
    function upgradeAccounts(address[] accounts) external;

    function upgradePassportCode(TvmCell code) external;
    function upgradePassports(
        address[] passports
    ) external;

    function upgrade(
        TvmCell code
    ) external;

    function getAccountPlatformCodeHash() external returns(uint);
    function getPassportPlatformCodeHash() external returns(uint);

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
        address rewarder,
        uint128 reward_fee,
        uint128 lp_fee
    ) external;

    function removeFarming(
        address farming_pool
    ) external;

    function setLpFee(
        address[] accounts,
        uint128 fee
    ) external;

    function setRewarder(
        address[] accounts,
        address _rewarder
    ) external;

    function setRewardFee(
        address[] accounts,
        uint128 fee
    ) external;

    function setManagers(
        address[] passports,
        uint[] _managers
    ) external;

    function getDetails() external returns (
        uint _version,
        uint[] _managers,
        address _rewarder,
        address _ping_token_root,
        address _ping_token_wallet,
        uint128 _ping_cost,
        mapping (address => FarmingPoolSettings) _farmings,

        TvmCell _account_platform,
        TvmCell _account_implementation,
        uint _account_version,

        TvmCell _passport_platform,
        TvmCell _passport_implementation,
        uint _passport_version
    );

    function receiveTokenWallet(
        address wallet
    ) external;

    event PassportDeployed(address owner, address passport);
    event AccountDeployed(address owner, address account);
}
