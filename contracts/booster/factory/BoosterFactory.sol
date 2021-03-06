pragma ton-solidity ^0.57.1;


import "broxus-ton-tokens-contracts/contracts/interfaces/IAcceptTokensTransferCallback.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenRoot.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";
import '@broxus/contracts/contracts/utils/RandomNonce.sol';

import "./../interfaces/IBoosterFactory.sol";
import "./BoosterFactoryBase.sol";

import "./../account/BoosterAccount_V1.sol";
import "./../account/BoosterAccountPlatform.sol";

import "./../passport/BoosterPassport.sol";
import "./../passport/BoosterPassportPlatform.sol";


contract BoosterFactory is IAcceptTokensTransferCallback, IBoosterFactory, BoosterFactoryBase, RandomNonce {
    constructor(
        address _owner,
        uint[] _managers,
        address _rewarder,
        address _ping_token_root,
        TvmCell _account_platform,
        TvmCell _account_implementation,
        TvmCell _passport_platform,
        TvmCell _passport_implementation
    ) public BoosterFactoryBase(_owner) {
        tvm.accept();

        managers = _managers;
        rewarder = _rewarder;
        ping_token_root = _ping_token_root;

        account_platform = _account_platform;
        account_implementation = _account_implementation;
        account_version = 0;

        passport_platform = _passport_platform;
        passport_implementation = _passport_implementation;
        passport_version = 0;

        ITokenRoot(ping_token_root).deployWallet{
            value: Gas.DEPLOY_TOKEN_WALLET * 2,
            callback: BoosterFactory.receiveTokenWallet
        }(
            address(this),
            Gas.DEPLOY_TOKEN_WALLET
        );
    }

    function receiveTokenWallet(
        address wallet
    ) external override {
        require(msg.sender == ping_token_root);

        ping_token_wallet = wallet;
    }

    /// @notice Derive booster account
    /// @param _owner Owner address
    /// @param farming_pool Farming pool address
    /// @return Booster account address
    function deriveAccount(
        address _owner,
        address farming_pool
    ) external override responsible returns(address) {
        TvmCell stateInit = _buildAccountPlatformStateInit(_owner, farming_pool);

        return {value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS} address(tvm.hash(stateInit));
    }

    /// @notice Derive passport
    /// @param _owner Owner address
    /// @return Passport address
    function derivePassport(
        address _owner
    ) external override responsible returns(address) {
        TvmCell stateInit = _buildPassportPlatformStateInit(_owner);

        return {value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS} address(tvm.hash(stateInit));
    }

    /// @notice Accepts tokens transfer
    function onAcceptTokensTransfer(
        address tokenRoot,
        uint128 amount,
        address sender,
        address,
        address remainingGasTo,
        TvmCell payload
    ) external override reserveBalance {
        // Send tokens back if wrong token received
        if (tokenRoot != ping_token_root || msg.sender != ping_token_wallet) {
            _transferTokens(
                msg.sender,
                amount,
                sender,
                remainingGasTo,
                false,
                payload,
                0,
                MsgFlag.ALL_NOT_RESERVED,
                false
            );

            return;
        }

        // Top up specified passport
        (address passport, bool deploy_passport, uint128 max_ping_price) = abi.decode(payload, (address, bool, uint128));

        TvmCell passportStateInit = _buildPassportPlatformStateInit(sender);

        if (deploy_passport) {
            _deployPassport(sender, passportStateInit, max_ping_price);
        }

        IBoosterPassport(passport).acceptPingTokens{
            value: 0,
            bounce: false,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(amount, remainingGasTo);
    }

    /// @notice Withdraw ping tokens on user's behalf
    /// Can be called only by correct passport
    /// @notice _owner Passport owner, used for address-derivation check
    /// @param amount Amount of tokens to withdraw
    function withdrawPingTokens(
        address _owner,
        uint128 amount,
        address remainingGasTo
    ) external override onlyBoosterPassport(_owner) reserveAtLeastTargetBalance {
        TvmCell empty;

        _transferTokens(
            ping_token_wallet,
            amount,
            _owner,

            remainingGasTo,
            false,
            empty,

            0,
            MsgFlag.ALL_NOT_RESERVED,
            true
        );
    }

    /// @notice Claim ping tokens, marked as "spent"
    /// Can be called only by `owner`
    /// Tokens will be transferred to the `owner`
    function claimSpentPingTokens() external override onlyOwner reserveAtLeastTargetBalance {
        TvmCell empty;

        _transferTokens(
            ping_token_wallet,
            ping_spent,
            owner,

            msg.sender,
            false,
            empty,

            0,
            MsgFlag.ALL_NOT_RESERVED,
            true
        );

        ping_spent = 0;
    }

    /// @notice Deploy booster account
    /// One booster account per (user, farming pool)
    /// @param farming_pool Farming pool address
    /// @param ping_frequency Desired ping frequency
    /// @param max_ping_price Max price per ping in ping_token
    /// @param deploy_passport Deploy passport or not
    function deployAccount(
        address farming_pool,
        uint64 ping_frequency,
        uint128 max_ping_price,
        bool deploy_passport
    ) external override reserveBalance farmingPoolExists(farming_pool) {
        require(ping_frequency >= Constants.MIN_PING_FREQUENCY, Errors.BOOSTER_PASSPORT_PING_FREQUENCY_TOO_LOW);

        FarmingPoolSettings settings = farmings[farming_pool];

        require(settings.enabled, Errors.BOOSTER_FACTORY_FARMING_POOL_DISABLED);

        TvmCell accountStateInit = _buildAccountPlatformStateInit(msg.sender, farming_pool);
        TvmCell passportStateInit = _buildPassportPlatformStateInit(msg.sender);

        address passport = address(tvm.hash(passportStateInit));
        address account = address(tvm.hash(accountStateInit));

        // Deploy passport if required
        if (deploy_passport) {
            _deployPassport(msg.sender, passportStateInit, max_ping_price);
        }

        // Register booster account in passport
        IBoosterPassport(passport).registerAccount{
            value: Gas.BOOSTER_FACTORY_PASSPORT_UPDATE,
            bounce: false
        }(
            account, // account
            farming_pool,
            ping_frequency, // ping frequency
            msg.sender // remaining gas
        );

        emit AccountDeployed(msg.sender, account);

        // Deploy booster account
        new BoosterAccountPlatform{
            stateInit: accountStateInit,
            value: 0,
            bounce: false,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(
            account_implementation, // account code
            account_version, // account version
            passport, // owner's passport
            settings, // farming settings
            msg.sender // remaining gas
        );
    }

    function _deployPassport(
        address owner,
        TvmCell passportStateInit,
        uint128 max_ping_price
    ) internal view {
        new BoosterPassportPlatform{
            stateInit: passportStateInit,
            value: Gas.BOOSTER_PASSPORT_TARGET_BALANCE + 1 ton,
            bounce: false,
            flag: 0
        }(
            passport_implementation,
            passport_version,
            managers,
            max_ping_price,
            owner
        );

        emit PassportDeployed(owner, address(tvm.hash(passportStateInit)));
    }

    /// @notice Upgrade booster account code
    /// Can be called only by `owner`
    /// @param _account_implementation New booster account code
    function upgradeAccountCode(
        TvmCell _account_implementation
    ) external override onlyOwner cashBack(owner) {
        account_implementation = _account_implementation;
        account_version++;
    }

    /// @notice Upgrade passport code
    /// Can be called only by `owner`
    /// @param _passport_implementation New booster passport code
    function upgradePassportCode(
        TvmCell _passport_implementation
    ) external override onlyOwner cashBack(owner) {
        passport_implementation = _passport_implementation;
        passport_version++;
    }

    /// @notice Upgrade booster passports code
    /// Can be called ony by `owner`
    /// @param passports List of passport accounts to upgrade
    function upgradePassports(
        address[] passports
    ) external override reserveBalance onlyOwner {
        require(passports.length <= 100);

        for (address passport_: passports) {
            IBoosterPassport(passport_).acceptUpgrade{
                value: Gas.BOOSTER_FACTORY_PASSPORT_UPGRADE,
                bounce: true
            }(passport_implementation, passport_version);
        }
    }

    /// @notice Upgrade booster accounts code
    /// @param accounts List of booster accounts to upgrade
    function upgradeAccounts(
        address[] accounts
    ) external override reserveBalance onlyOwner {
        require(accounts.length <= 100);

        for (address account_: accounts) {
            IBoosterAccount(account_).acceptUpgrade{
                value: Gas.BOOSTER_FACTORY_ACCOUNT_UPGRADE,
                bounce: true
            }(account_implementation, account_version);
        }
    }

    function getAccountPlatformCodeHash() external override returns (uint) {
        return tvm.hash(account_platform);
    }

    function getPassportPlatformCodeHash() external override returns (uint) {
        return tvm.hash(passport_platform);
    }

    function encodePingTopUp(
        address passport,
        bool deploy_passport,
        uint128 max_ping_price
    ) external pure returns(TvmCell) {
        return abi.encode(passport, deploy_passport, max_ping_price);
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

        tvm.setcode(code);
        tvm.setCurrentCode(code);

        onCodeUpgrade(data);
    }

    function onCodeUpgrade(TvmCell data) private {
        tvm.resetStorage();

        (
            uint _randomNonce_,
            address _owner,
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
        ) = abi.decode(
            data,
            (
                uint, address, uint, uint[], address,
                address, address, mapping(address => FarmingPoolSettings),
                TvmCell, TvmCell, uint,
                TvmCell, TvmCell, uint
            )
        );

        _randomNonce = _randomNonce_;
        setOwnership(_owner);
        version = _version + 1;
        managers = _managers;
        rewarder = _rewarder;

        ping_token_root = _ping_token_root;
        ping_token_wallet = _ping_token_wallet;
        farmings = _farmings;

        account_platform = _account_platform;
        account_implementation = _account_implementation;
        account_version = _account_version;

        passport_platform = _passport_platform;
        passport_implementation = _passport_implementation;
        passport_version = _passport_version;
    }
}
