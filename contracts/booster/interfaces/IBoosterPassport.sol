pragma ton-solidity ^0.57.1;


interface IBoosterPassport {
    struct AccountSettings {
        address farming_pool;
        uint64 ping_frequency;
        uint64 last_ping;
        uint64 ping_counter;
        bool auto_ping_enabled;
    }

    function acceptUpgrade(
        TvmCell code,
        uint version
    ) external;

    function acceptPingTokens(
        uint128 amount,
        address remainingGasTo
    ) external;

    function withdrawPingToken(
        uint128 amount,
        address remainingGasTo
    ) external;

    function registerAccount(
        address account,
        address farming_pool,
        uint64 ping_frequency,
        address remainingGasTo
    ) external;

    function setPingFrequency(
        address account,
        uint64 frequency
    ) external;

    function setPingMaxPrice(
        uint128 price
    ) external;

    function setManagers(
        uint[] managers,
        address remainingGasTo
    ) external;

    function toggleAccountAutoPing(
        address account
    ) external;

    function pingByManager(
        uint128 price,
        address account,
        uint64 counter
    ) external;

    function pingByOwner(
        address account,
        uint64 counter
    ) external;

    function getDetails() external view returns(
        address _owner,
        address _factory,
        uint _version,
        uint[] _managers,
        uint128 _ping_balance,
        uint128 _ping_max_price,
        mapping (address => AccountSettings) _accounts
    );

    event PingTokensAccepted(uint128 amount);
    event PingTokensWithdrawn(uint128 amount);

    event AccountRegistered(address account);
    event PingFrequencyUpdated(address account, uint64 frequency);
    event PingMaxPriceUpdated(uint128 price);
    event AutoPingUpdated(address account, bool status);
    event Ping(address account, uint64 _timestamp, uint64 counter, bool byManager);
    event ManagersUpdated(uint[] managers);
}
