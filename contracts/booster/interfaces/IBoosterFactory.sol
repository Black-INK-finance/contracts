pragma ton-solidity ^0.57.1;

import "./IBoosterBase.sol";


interface IBoosterFactory is IBoosterBase {
    function skimGas(
        uint128 reserve
    ) external;

    function pingAccount(
        address _owner,
        uint64 counter,
        address account,
        address farming_pool,
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
        uint64 ping_frequency,
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
        uint128 lp_fee,
        uint128 ping_value
    ) external;

    function setPingValue(
        address farming_pool,
        uint128 ping_value
    ) external;

    function setRewarder(
        address farming_pool,
        address[] accounts,
        address rewarder,
        bool save_as_default
    ) external;

    function setFees(
        address farming_pool,
        address[] accounts,
        uint128 lp_fee,
        uint128 reward_fee,
        bool save_as_default
    ) external;

    function toggleFarming(
        address farming_pool
    ) external;

    function skimFees(
        address[] accounts
    ) external;

    function setManagers(
        address[] passports,
        uint[] _managers,
        bool save_as_default
    ) external;

    function getDetails() external returns (
        uint _version,
        uint[] _managers,
        address _rewarder,
        address _ping_token_root,
        address _ping_token_wallet,
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
