pragma ton-solidity ^0.57.1;


import "./../interfaces/IBoosterFactory.sol";
import "./../interfaces/IBoosterAccount.sol";
import "./../interfaces/IBoosterPassport.sol";

import "@broxus/contracts/contracts/access/InternalOwner.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";

import "./../Constants.sol";
import "./../Errors.sol";
import "./../Gas.sol";

abstract contract BoosterFactoryStorage is IBoosterFactory, InternalOwner {
    uint public version;
    uint[] public managers;
    address public rewarder;
    address public ping_token_root;
    address public ping_token_wallet;
    uint128 public ping_spent;

    mapping (address => FarmingPoolSettings) public farmings;

    TvmCell public account_platform;
    TvmCell public account_implementation;
    uint public account_version;

    TvmCell public passport_platform;
    TvmCell public passport_implementation;
    uint public passport_version;

    modifier farmingPoolExists(address farming_pool) {
        require(farmings.exists(farming_pool), Errors.BOOSTER_FACTORY_FARMING_POOL_NOT_EXISTS);

        _;
    }

    function getDetails() responsible external override returns (
        uint _version,
        uint[] _managers,
        address _rewarder,

        address _ping_token_root,
        address _ping_token_wallet,

        mapping (address => FarmingPoolSettings) _farmings,

        TvmCell _account_platform,
        TvmCell _account_implementation,
        uint _account_version,

        TvmCell _passport_platform,
        TvmCell _passport_implementation,
        uint _passport_version
    ) {
        return {value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS}(
            version,
            managers,
            rewarder,

            ping_token_root,
            ping_token_wallet,

            farmings,

            account_platform,
            account_implementation,
            account_version,

            passport_platform,
            passport_implementation,
            passport_version
        );
    }

    function _me() internal pure returns(address) {
        return address(this);
    }
}
