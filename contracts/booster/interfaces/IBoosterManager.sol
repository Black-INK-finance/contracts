pragma ton-solidity ^0.57.1;


interface IBoosterManager {
    struct Ping {
        address account;
        bool skim;
    }

    function ping(
        Ping[] pings
    ) external;
}
