pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "./../interfaces/IBoosterAccount.sol";
import "./BoosterAccountBase.sol";
import "./../Utils.sol";

import "broxus-ton-tokens-contracts/contracts/interfaces/IAcceptTokensTransferCallback.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/IAcceptTokensMintCallback.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";


contract BoosterAccount is
    IBoosterAccount,
    IAcceptTokensTransferCallback,
    IAcceptTokensMintCallback,
    BoosterAccountBase
{
    function onCodeUpgrade(
        TvmCell data
    ) private {
        tvm.resetStorage();

        (
            address _factory,
            address _farming_pool,
            uint _version,

            address _owner,
            address _manager,
            FarmingPoolSettings _settings
        ) = abi.decode(
            data,
            (
                address, address, uint,
                address, address, FarmingPoolSettings
            )
        );

        factory = _factory;
        farming_pool = _farming_pool;
        version = _version;

        setOwnership(_owner);
        manager = _manager;
        settings = _settings;

        _requestFarmingUserData();

        // Setup token wallets for involved tokens
        // - Pair LP
        _deployTokenWallet(settings.lp);
        // - Pair left
        _deployTokenWallet(settings.left);
        // - Pair right
        _deployTokenWallet(settings.right);

        // - Farming pool rewards
        for (address reward: settings.rewards) {
            _deployTokenWallet(reward);
        }

        // - Tokens involved in swaps
        for ((address _from, SwapDirection direction): settings.swaps) {
            if (!tokens.exists(_from)) {
                _deployTokenWallet(_from);
            }

            if (!tokens.exists(direction.token)) {
                _deployTokenWallet(direction.token);
            }
        }
    }

    /// @notice Keeper method for claiming farming reward
    /// Can be called only by `owner` or `manager`
    /// @param skim Skim fees or not. Only manager can specify skim = true
    function ping(bool skim) external override onlyOwnerOrManager {
        if (skim) {
            // Only manager can skim fees
            require(msg.sender == manager);

            _skimFees();
        }

        last_ping = now;

        _claimReward();
    }

    /// @notice Receive tokens
    /// Only few tokens are acceptable, any other token will be sent to the owner
    /// @param root Transferred token root
    /// @param amount Transfer amount
    /// @param sender Token sender
    /// @param payload Cell-encoded payload
    function onAcceptTokensTransfer(
        address root,
        uint128 amount,
        address sender,
        address,
        address,
        TvmCell payload
    ) external override {
        // Transfer tokens to the owner (not sender!) in case:
        // - token root not initialized (eg some third party token was sent)
        // - msg.sender is different from the actual token wallet (eg booster token wallet is still not initialized)
        // - reinvesting is paused
        if (!tokens.exists(root) || msg.sender != tokens[root].wallet || paused == true) {
            TvmCell empty;

            _transferTokens(
                msg.sender,
                amount,
                owner,
                _me(),
                false,
                empty,
                0,
                MsgFlag.REMAINING_GAS
            );

            return;
        }

        if (_isArrayIncludes(root, settings.rewards) && sender == farming_pool) {
            // Get management fees from reward, which are sent from the farming pool
            uint128 fee = math.muldivr(
                amount,
                settings.fee,
                Utils.BPS
            );

            // Consider fees
            _considerTokensFee(root, fee);
            _considerTokensArrival(root, amount - fee);

            // Check reward transfer payload
            (uint32 nonce) = abi.decode(payload, (uint32));

            if (nonce == NO_REINVEST_REQUIRED) return;
        } else {
            _considerTokensArrival(root, amount);
        }

        _processTokensArrival(root);
    }

    /// @notice Accepts tokens mint
    /// Only few tokens are acceptable, any other token will be sent to the owner
    /// @param root Transferred token root
    /// @param amount Transfer amount
    function onAcceptTokensMint(
        address root,
        uint128 amount,
        address,
        TvmCell
    ) external override {
        if (!tokens.exists(root) || tokens[root].wallet != msg.sender || paused == true) {
            TvmCell empty;

            _transferTokens(
                msg.sender,
                amount,
                owner,
                _me(),
                false,
                empty,
                0,
                MsgFlag.REMAINING_GAS
            );

            return;
        }

        _considerTokensArrival(root, amount);
        _processTokensArrival(root);
    }

    function _considerTokensFee(address token, uint128 amount) internal {
        tokens[token].fee += amount;
    }

    function _considerTokensArrival(address token, uint128 amount) internal {
        tokens[token].balance += amount;
        tokens[token].received += amount;
    }

    function _processTokensArrival(address token) internal {
        // Handle received token
        if (token == settings.lp) {
            // - Received token is LP, deposit it into farming
            _depositToFarming();
        } else if (token == settings.left || token == settings.right) {
            // - Received token is pool left or right, deposit it to pair
            _depositLiquidityToPair(token);
        } else if (settings.swaps.exists(token)) {
            // - Received token should be swapped
            _swap(token);
        }
    }

    /// @notice Upgrade account
    /// Can be called only by `factory`
    /// Upgrade ignored if `_version` is the same as current one
    /// @param code New account code
    /// @param _version New account version
    function acceptUpgrade(
        TvmCell code,
        uint _version
    ) external override onlyFactory {
        if (version == _version) return;

        TvmCell data = abi.encode(
            owner, _version, factory, farming_pool,
            last_ping, paused, manager,
            user_data, settings, tokens
        );

        tvm.setcode(code);
        tvm.setCurrentCode(code);

        onCodeUpgrade(data);
    }

//    function onCodeUpgrade(TvmCell data) private {
//        (
//            address _owner,
//            uint _version,
//            address _factory,
//            address _farming_pool,
//
//            uint _last_ping,
//            bool _paused,
//            address _admin,
//
//            address _rewarder,
//            address _dex,
//            uint128 _fee,
//
//            address _user_data,
//            address _lp,
//            address _left,
//            address _right,
//
//            address _rewards,
//            mapping (address => Token) _tokens
//        ) = abi.decode(
//            data,
//            (
//                address, uint, address, address,
//                uint, uint, bool, address,
//                address, address, uint128, address,
//                address, address, address, address,
//                address, mapping (address => Token)
//            )
//        );
//
//        setOwnership(_owner);
//        version = _version;
//        factory = _factory;
//        farming_pool = _farming_pool;
//
//        last_ping = _last_ping;
//        paused = _paused;
//        admin = _admin;
//
//        rewarder = _rewarder;
//        dex = _dex;
//        fee = _fee;
//
//        user_data = _user_data;
//        lp = _lp;
//        left = _left;
//        right = _right;
//
//        rewards = _rewards;
//        tokens = _tokens;
//    }
}
