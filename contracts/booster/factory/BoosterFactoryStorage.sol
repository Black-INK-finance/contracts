pragma ton-solidity ^0.57.1;


import "../interfaces/IBoosterFactory.sol";
import "@broxus/contracts/contracts/access/InternalOwner.sol";


abstract contract BoosterFactoryStorage is IBoosterFactory, InternalOwner {
    uint public version;
    address public manager;
    mapping (address => FarmingPoolSettings) public farmings;

    TvmCell public account_platform;
    TvmCell public account;
    uint public account_version;

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
