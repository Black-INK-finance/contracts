pragma ton-solidity ^0.57.1;


interface IBoosterManager {
    struct Ping {
        address account;
        bool skim;
    }

    function ping(
        Ping[] pings
    ) external;

    function upgrade(
        TvmCell code
    ) external;

    function getDetails() external view returns(uint _owner, address _internalOwner, uint _version);
}
