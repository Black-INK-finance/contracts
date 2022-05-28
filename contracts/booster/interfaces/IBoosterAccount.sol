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
        FarmingPoolSettings _settings,
        mapping (address => Token) _tokens
    );

    // Manager methods
    function ping(bool skim) external;

    // Factory methods
    function setFee(uint128 _fee) external;
    function acceptUpgrade(
        TvmCell code,
        uint version
    ) external;

    function isNeedPing() external view returns(bool);
    function isInitialized() external view returns(bool);

    // Owner methods
    function setPaused(bool _paused) external;
    function withdraw(address token, uint128 _amount) external;
    function requestFarmingLP(
        uint128 amount
    ) external;

    // Technical methods
    function receiveTokenWallet(address wallet) external;
    function receiveFarmingUserData(address _user_data) external;
}
