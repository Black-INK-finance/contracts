pragma ton-solidity ^0.57.1;


import "../interfaces/IBoosterFactory.sol";
import "@broxus/contracts/contracts/access/InternalOwner.sol";


abstract contract BoosterFactoryStorage is IBoosterFactory, InternalOwner {
    uint public version;
    address public manager;
    address public rewarder;
    address public ping_token_root;
    address public ping_token_wallet;
    uint128 public recommended_ping_price_limit;
    mapping (address => FarmingPoolSettings) public farmings;

    TvmCell public account_platform;
    TvmCell public account;
    uint public account_version;

    function getDetails() external override returns (
        uint _version,
        address _manager,
        address _rewarder,
        address _ping_token_root,
        address _ping_token_wallet,
        uint128 _recommended_ping_price_limit,
        mapping (address => FarmingPoolSettings) _farmings,
        TvmCell _account_platform,
        TvmCell _account,
        uint _account_version
    ) {
        return (
            version,
            manager,
            rewarder,

            ping_token_root,
            ping_token_wallet,
            recommended_ping_price_limit,

            farmings,
            account_platform,
            account,
            account_version
        );
    }
}
