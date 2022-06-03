pragma ton-solidity ^0.57.1;


import "broxus-ton-tokens-contracts/contracts/interfaces/IAcceptTokensTransferCallback.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenRoot.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";
import '@broxus/contracts/contracts/utils/RandomNonce.sol';

import "./../interfaces/IBoosterFactory.sol";
import "./BoosterFactoryBase.sol";

import "./../account/BoosterAccount_V1.sol";
import "./../account/BoosterAccountPlatform.sol";


contract BoosterFactory is IAcceptTokensTransferCallback, IBoosterFactory, BoosterFactoryBase, RandomNonce {
    constructor(
        address _owner,
        address _manager,
        address _rewarder,
        address _ping_token_root,
        uint128 _recommended_ping_price_limit,
        TvmCell _account_platform,
        TvmCell _account
    ) public BoosterFactoryBase(_owner) {
        tvm.accept();

        ping_token_root = _ping_token_root;
        recommended_ping_price_limit = _recommended_ping_price_limit;
        manager = _manager;
        rewarder = _rewarder;
        account_platform = _account_platform;
        account = _account;

        account_version = 0;

        ITokenRoot(ping_token_root).deployWallet{
            value: Utils.DEPLOY_TOKEN_WALLET * 2,
            callback: BoosterFactory.receiveTokenWallet
        }(
            address(this),
            Utils.DEPLOY_TOKEN_WALLET
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
    function deriveAccount(
        address _owner,
        address farming_pool
    ) external override responsible returns(address) {
        TvmCell stateInit = _buildAccountPlatformStateInit(_owner, farming_pool);

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
        if (tokenRoot != ping_token_root || msg.sender != ping_token_wallet || msg.value < Utils.BOOSTER_FACTORY_TOP_UP_MIN) {
            _transferTokens(
                msg.sender,
                amount,
                sender,
                remainingGasTo,
                true,
                payload,
                0,
                MsgFlag.ALL_NOT_RESERVED,
                false
            );
        }

        // Transfer tokens to owner
        TvmCell empty;

        _transferTokens(
            ping_token_wallet,
            amount,
            rewarder,
            remainingGasTo,
            false,
            empty,
            Utils.BOOSTER_FACTORY_THROW_PING_TOKENS,
            0,
            true
        );

        // Top up specified account
        (address account) = abi.decode(payload, (address));

        IBoosterAccount(account).acceptPingTokens{
            value: 0,
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
    /// @param _owner Booster account owner
    /// @param farming_pool Farming pool address
    function deployAccount(
        address _owner,
        address farming_pool
    ) external override reserveBalance {
        require(farmings.exists(farming_pool));
        require(msg.value >= Utils.BOOSTER_DEPLOY_ACCOUNT);

        TvmCell stateInit = _buildAccountPlatformStateInit(_owner, farming_pool);

        FarmingPoolSettings settings = farmings[farming_pool];
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
            recommended_ping_price_limit, // recommended ping price limit
            settings // farming settings
        );
    }

    /// @notice Update recommended price limit
    /// @param limit New recommended price limit
    function setRecommendedPriceLimit(
        uint128 limit
    ) external override onlyOwner {
        require(limit > 0);

        recommended_ping_price_limit = limit;
    }

    /// @notice Upgrade booster account code
    /// Can be called only by `owner`
    /// @param _account New booster account code
    function upgradeAccountCode(
        TvmCell _account
    ) external override onlyOwner cashBack(owner) {
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

    function encodePingTopUp(
        address account
    ) external override pure returns(TvmCell) {
        return abi.encode(account);
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
            rewarder,
            ping_token_root,
            ping_token_wallet,
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
            address _rewarder,

            address _ping_token_root,
            address _ping_token_wallet,
            uint _version,

            TvmCell _account_platform,
            TvmCell _account,
            uint _account_version,
            mapping (address => FarmingPoolSettings) _farmings
        ) = abi.decode(
            data,
            (
                uint, address, address, address, address, address, uint,
                TvmCell, TvmCell, uint, mapping(address => FarmingPoolSettings)
            )
        );

        _randomNonce = _randomNonce_;
        setOwnership(_owner);
        manager = _manager;
        rewarder = _rewarder;

        ping_token_root = _ping_token_root;
        ping_token_wallet = _ping_token_wallet;
        version = _version + 1;

        account_platform = _account_platform;
        account = _account;
        account_version = _account_version;
        farmings = _farmings;
    }
}
