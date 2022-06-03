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

        uint _last_ping,
        bool _paused,
        address _manager,
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
        uint256 _ping_frequency,
        address _rewarder,
        uint128 _reward_fee,
        uint128 _lp_fee
    );

    // Manager methods
    function ping(
        uint128 price,
        bool skim
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
    function acceptUpgrade(
        TvmCell code,
        uint version
    ) external;
    function acceptPingTokens(
        uint128 amount,
        address remainingGasTo
    ) external;
    function setManager(
        address _manager,
        address remainingGasTo
    ) external;

    function isNeedPing(uint128 price) external view returns(bool);
    function isInitialized() external view returns(bool);

    // Owner methods
    function setPaused(bool _paused) external;
    function withdraw(address token, uint128 _amount) external;
    function requestFarmingLP(
        uint128 amount
    ) external;
    function setPingFrequency(
        uint _ping_frequency
    ) external;

    // Technical methods
    function receiveTokenWallet(address wallet) external;
    function receiveFarmingUserData(address _user_data) external;
}
