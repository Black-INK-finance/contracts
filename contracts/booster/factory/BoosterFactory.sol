pragma ton-solidity ^0.57.1;


import '@broxus/contracts/contracts/utils/RandomNonce.sol';

import "./../interfaces/IBoosterFactory.sol";
import "./BoosterFactoryBase.sol";

import "./../account/BoosterAccount_V1.sol";
import "./../account/BoosterAccountPlatform.sol";


contract BoosterFactory is IBoosterFactory, BoosterFactoryBase, RandomNonce {
    constructor(
        address _owner,
        address _manager,
        TvmCell _account_platform,
        TvmCell _account
    ) public BoosterFactoryBase(_owner) {
        tvm.accept();

        manager = _manager;
        account_platform = _account_platform;
        account = _account;

        account_version = 0;
    }

    /// @notice Derive booster account
    /// @param _owner Owner address
    /// @param farming_pool Farming pool address
    function deriveAccount(
        address _owner,
        address farming_pool
    ) external override responsible returns(address) {
        TvmCell stateInit = _buildAccountPlatformStateInit(_owner, farming_pool);

        return {value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS} address(tvm.hash(stateInit));
    }

    /// @notice Deploy booster account
    /// @param _owner Booster account owner
    /// @param farming_pool Farming pool address
    /// @param ping_frequency Ping frequency, chosen by user
    function deployAccount(
        address _owner,
        address farming_pool,
        uint256 ping_frequency
    ) external override reserveBalance {
        require(farmings.exists(farming_pool));
        require(msg.value >= Utils.BOOSTER_DEPLOY_ACCOUNT);
        require(ping_frequency >= Utils.MIN_PING_FREQUENCY);

        TvmCell stateInit = _buildAccountPlatformStateInit(_owner, farming_pool);

        FarmingPoolSettings settings = farmings[farming_pool];
        settings.ping_frequency = ping_frequency;

        require(settings.paused == false);

        new BoosterAccountPlatform{
            stateInit: stateInit,
            value: 0,
            bounce: false,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(
            account, // account code
            account_version, // account version
            manager, // manager
            settings // farming pool settings
        );
    }

    /// @notice Upgrade booster account code
    /// Can be called only by `owner`
    /// @param _account New booster account code
    function upgradeAccountCode(
        TvmCell _account
    ) external override cashBack onlyOwner {
        account = _account;
        account_version++;
    }

    /// @notice Upgrade booster accounts
    /// @param accounts List of booster accounts to upgrade
    function upgradeAccounts(
        address[] accounts
    ) external override reserveBalance onlyOwner {
        require(accounts.length <= 100);
        require(msg.value >= accounts.length * Utils.BOOSTER_UPGRADE_ACCOUNT + 10 ton);

        for (address account_: accounts) {
            IBoosterAccount(account_).acceptUpgrade{
                value: Utils.BOOSTER_UPGRADE_ACCOUNT
            }(account, account_version);
        }
    }

    function getAccountPlatformCodeHash() external override returns (uint) {
        return tvm.hash(account_platform);
    }

    /// @notice Upgrade booster factory
    /// Can be called only by `owner`
    /// @param code New factory code
    function upgrade(
        TvmCell code
    ) external override onlyOwner {
        TvmCell data = abi.encode(
            _randomNonce,
            owner,
            manager,
            version,
            account_platform,
            account,
            account_version,
            farmings
        );

        tvm.setcode(code);
        tvm.setCurrentCode(code);

        onCodeUpgrade(data);
    }

    function onCodeUpgrade(TvmCell data) private {
        tvm.resetStorage();

        (
            uint _randomNonce_,
            address _owner,
            address _manager,
            uint _version,

            TvmCell _account_platform,
            TvmCell _account,
            uint _account_version,
            mapping (address => FarmingPoolSettings) _farmings
        ) = abi.decode(
            data,
            (
                uint, address, address, uint,
                TvmCell, TvmCell, uint, mapping(address => FarmingPoolSettings)
            )
        );

        _randomNonce = _randomNonce_;
        setOwnership(_owner);
        manager = _manager;
        version = _version + 1;

        account_platform = _account_platform;
        account = _account;
        account_version = _account_version;
        farmings = _farmings;
    }
}
