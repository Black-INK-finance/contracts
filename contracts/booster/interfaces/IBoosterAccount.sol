pragma ton-solidity ^0.57.1;

import "./IBoosterBase.sol";


interface IBoosterAccount is IBoosterBase {
    struct Token {
        uint128 balance;
        uint128 received;
        address wallet;
        uint128 fee;
    }

    function getDetails() external view returns (
        address _owner,
        uint _version,
        address _factory,
        address _farming_pool,
        address _passport,
        address _user_data,

        mapping (address => uint128) _balances,
        mapping (address => uint128) _received,
        mapping (address => address) _wallets,
        mapping (address => uint128) _fees,

        address _lp,
        address _pair,
        address _left,
        address _right,
        address[] _rewards,

        mapping (address => SwapDirection) _swaps,
        address _rewarder,
        uint128 _reward_fee,
        uint128 _lp_fee
    );

    // Manager methods
    function ping(
        uint counter
    ) external;

    function skim() external;

    // Factory methods
    function setRewardFee(
        uint128 _fee,
        address remainingGasTo
    ) external;
    function setLpFee(
        uint128 _fee,
        address remainingGasTo
    ) external;
    function setRewarder(
        address _rewarder,
        address remainingGasTo
    ) external;
    function acceptUpgrade(
        TvmCell code,
        uint version
    ) external;

    function isInitialized() external view returns(bool);

    // Owner methods
    function requestFarmingLP(
        uint128 amount
    ) external;

    // Technical methods
    function receiveTokenWallet(address wallet) external;
    function receiveFarmingUserData(address _user_data) external;
}
