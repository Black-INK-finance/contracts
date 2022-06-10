pragma ton-solidity ^0.57.1;


interface IBoosterPassport {
    struct AccountSettings {
        uint128 ping_frequency;
        uint128 last_ping;
        uint ping_counter;
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

    function registerAccount(
        address account,
        uint128 ping_frequency,
        address remainingGasTo
    ) external;

    function setPingFrequency(
        address account,
        uint128 frequency
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
        uint counter
    ) external;

    function pingByOwner(
        address account,
        uint counter
    ) external;
}
