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
        uint128 _ping_cost,
        TvmCell _account_platform,
        TvmCell _account_implementation,
        TvmCell _passport_platform,
        TvmCell _passport_implementation
    ) public BoosterFactoryBase(_owner) {
        tvm.accept();

        managers = _managers;
        rewarder = _rewarder;
        ping_token_root = _ping_token_root;
        ping_cost = _ping_cost;

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

    /// @notice Update manager on specific accounts
    /// Can be called only by `owner`
    /// @param passports Accounts list
    /// @param _managers List of manager public keys
    function setManagers(
        address[] passports,
        uint[] _managers
    ) external override reserveBalance onlyOwner {
        for (address passport: passports) {
            IBoosterPassport(passport).setManagers{
                value: Gas.BOOSTER_FACTORY_ACCOUNT_UPDATE,
                bounce: true
            }(_managers, msg.sender);
        }
    }

    /// @notice Update reward fee on specific accounts
    /// Can be called only by `owner`
    /// @param accounts Accounts list
    /// @param fee Fee value in BPS
    function setRewardFee(
        address[] accounts,
        uint128 fee
    ) external override reserveBalance onlyOwner {
        require(fee <= Constants.MAX_FEE);

        for (address account: accounts) {
            IBoosterAccount(account).setRewardFee{
                value: Gas.BOOSTER_FACTORY_ACCOUNT_UPDATE,
                bounce: true
            }(fee, msg.sender);
        }
    }

    /// @notice Update LP fee on specific accounts
    /// Can be called only by `owner`
    /// @param accounts Accounts list
    /// @param fee Fee value in BPS
    function setLpFee(
        address[] accounts,
        uint128 fee
    ) external override reserveBalance onlyOwner {
        require(fee <= Constants.MAX_FEE);

        for (address account: accounts) {
            IBoosterAccount(account).setLpFee{
                value: Gas.BOOSTER_FACTORY_ACCOUNT_UPDATE,
                bounce: true
            }(fee, msg.sender);
        }
    }

    /// @notice Set rewarder address on specific accounts
    /// Can be called only by `owner`
    /// @param accounts Accounts list
    /// @param _rewarder New rewarder
    function setRewarder(
        address[] accounts,
        address _rewarder
    ) external override reserveBalance onlyOwner {
        /// A.K. protection
        require(_rewarder != address.makeAddrStd(0, 0));

        for (address account: accounts) {
            IBoosterAccount(account).setRewarder{
                value: Gas.BOOSTER_FACTORY_ACCOUNT_UPDATE,
                bounce: true
            }(_rewarder, msg.sender);
        }
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

        // Transfer tokens to owner
        TvmCell empty;

        _transferTokens(
            ping_token_wallet,
            amount,
            owner,
            remainingGasTo,
            false,
            empty,
            Gas.BOOSTER_FACTORY_THROW_PING_TOKENS,
            0,
            true
        );

        // Top up specified passport
        (address passport) = abi.decode(payload, (address));

        IBoosterPassport(passport).acceptPingTokens{
            value: 0,
            bounce: false,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(amount, remainingGasTo);
    }

    /// @notice Withdraw ping tokens from the factory
    /// Can be called only by `owner`
    /// Tokens will be transferred to the `owner`
    /// @param amount Amount of tokens to withdraw
    function withdrawPingTokens(
        uint128 amount
    ) external override onlyOwner reserveBalance {
        TvmCell empty;

        _transferTokens(
            ping_token_wallet,
            amount,
            owner,
            msg.sender,
            false,
            empty,
            0,
            MsgFlag.ALL_NOT_RESERVED,
            true
        );
    }

    /// @notice Deploy booster account
    /// One booster account per (user, farming pool)
    /// @param farming_pool Farming pool address
    function deployAccount(
        address farming_pool,
        uint128 ping_frequency,
        uint128 max_ping_price,
        bool deploy_passport
    ) external override reserveBalance {
        require(farmings.exists(farming_pool));
        require(ping_frequency >= Constants.MIN_PING_FREQUENCY);

        FarmingPoolSettings settings = farmings[farming_pool];

        TvmCell accountStateInit = _buildAccountPlatformStateInit(msg.sender, farming_pool);
        TvmCell passportStateInit = _buildPassportPlatformStateInit(msg.sender);

        address passport = address(tvm.hash(passportStateInit));
        address account = address(tvm.hash(accountStateInit));

        // Deploy passport if required
        if (deploy_passport) {
            new BoosterPassportPlatform{
                stateInit: passportStateInit,
                value: Gas.BOOSTER_PASSPORT_TARGET_BALANCE * 2,
                bounce: false,
                flag: 0
            }(
                passport_implementation,
                passport_version,
                managers,
                max_ping_price,
                msg.sender
            );
        }

        // Register booster account in passport
        IBoosterPassport(passport).registerAccount{
            value: Gas.BOOSTER_FACTORY_PASSPORT_UPDATE,
            bounce: false
        }(
            account, // account
            ping_frequency, // ping frequency
            msg.sender // remaining gas
        );

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
        address passport
    ) external override pure returns(TvmCell) {
        return abi.encode(passport);
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
            ping_cost,
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
            uint128 _ping_cost,
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
                address, address, uint128, mapping(address => FarmingPoolSettings),
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
        ping_cost = _ping_cost;
        farmings = _farmings;

        account_platform = _account_platform;
        account_implementation = _account_implementation;
        account_version = _account_version;

        passport_platform = _passport_platform;
        passport_implementation = _passport_implementation;
        passport_version = _passport_version;
    }
}
