pragma ton-solidity ^0.57.1;


import "../interfaces/IBoosterFactory.sol";
import "@broxus/contracts/contracts/access/InternalOwner.sol";


abstract contract BoosterFactoryStorage is IBoosterFactory, InternalOwner {
    uint version;
    address manager;
    mapping (address => FarmingPoolSettings) farmings;

    TvmCell account_platform;
    TvmCell account;
    uint account_version;

    function getDetails() external override returns (
        uint _version,
        address _manager,
        mapping (address => FarmingPoolSettings) _farmings,
        TvmCell _account_platform,
        TvmCell _account,
        uint _account_version
    ) {
        return (
            version,
            manager,
            farmings,
            account_platform,
            account,
            account_version
        );
    }
}
