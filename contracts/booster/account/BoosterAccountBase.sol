pragma ton-solidity ^0.57.1;


import "@broxus/contracts/contracts/libraries/MsgFlag.sol";

import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenRoot.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/IAcceptTokensTransferCallback.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/IAcceptTokensMintCallback.sol";

import "flatqube/contracts/interfaces/IDexRoot.sol";
import "flatqube/contracts/interfaces/IDexAccount.sol";
import "flatqube/contracts/libraries/DexOperationTypes.sol";

import "./../../v3/interfaces/IEverFarmPool.sol";

import "./BoosterAccountSettings.sol";
import "./../Utils.sol";


abstract contract BoosterAccountBase is
    InternalOwner,
    IAcceptTokensTransferCallback,
    IAcceptTokensMintCallback,
    BoosterAccountSettings
{
    /// @notice Returns all exceeding balance to the manager
    /// `_targetBalance()` is used as a baseline
    receive() external view {
        tvm.rawReserve(_targetBalance(), 0);

        manager.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    constructor() public {
        revert();
    }

    /// @notice Accept ping token top up
    /// Can be called only by `factory`
    /// @param amount Amount of ping tokens to accept
    function acceptPingTokens(
        uint128 amount,
        address remainingGasTo
    ) external override onlyFactory cashBack(remainingGasTo) {
        ping_balance += amount;
    }

    /// @notice Keeper method for claiming farming reward
    /// Can be called only by `owner` or `manager`
    /// @param price Ping price in PING tokens, needs to compensate keeper charges
    /// @param skim Boolean, skim requested or not. If `false`, then fees won't be skimmed, use `skim` method.
    /// Otherwise, fees will be skimmed each `Utils.PINGS_PER_SKIM` ping.
    function ping(
        uint128 price,
        bool skim
    ) external override onlyOwnerOrManager {
        require(price <= ping_price_limit);
        tvm.accept();

        last_ping = now;
        ping_counter++;

        if (msg.sender == manager) {
            ping_balance -= price;
        }

        if (skim && ping_counter % Utils.PINGS_PER_SKIM == 0) {
            _skimFees();
        }

        _claimReward();
    }

    /// @notice Keeper method for skimming fees
    /// Can be called only by `manager`
    function skim() external override onlyManager {
        tvm.accept();

        _skimFees();
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
        if (!wallets.exists(root) || msg.sender != wallets[root] || paused == true) {
            TvmCell empty;

            _transferTokens(
                msg.sender,
                amount,
                owner,
                _me(),
                true,
                empty,
                0,
                MsgFlag.REMAINING_GAS,
                true
            );

            return;
        }

        if (_isArrayIncludes(root, rewards) && sender == farming_pool) {
            // Get management fees from reward, which are sent from the farming pool
            uint128 fee = math.muldivr(amount, reward_fee, Utils.BPS);

            // Consider fees
            _considerTokensFee(root, fee);
            _considerTokensArrival(root, amount - fee);

            // Check reward transfer payload
            (uint32 nonce) = abi.decode(payload, (uint32));

            if (nonce == Utils.NO_REINVEST_REQUIRED) return;
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
        if (!wallets.exists(root) || wallets[root] != msg.sender || paused == true) {
            TvmCell empty;

            _transferTokens(
                msg.sender,
                amount,
                owner,
                _me(),
                false,
                empty,
                0,
                MsgFlag.REMAINING_GAS,
                true
            );

            return;
        }

        if (root == lp) {
            uint128 fee = math.muldivr(amount, lp_fee, Utils.BPS);

            _considerTokensFee(lp, fee);
            _considerTokensArrival(lp, amount - fee);
        } else {
            _considerTokensArrival(root, amount);
        }

        _processTokensArrival(root);
    }

    function _considerTokensFee(
        address token,
        uint128 amount
    ) internal {
        fees[token] += amount;
    }

    function _considerTokensArrival(
        address token,
        uint128 amount
    ) internal {
        balances[token] += amount;
        received[token] += amount;
    }

    function _processTokensArrival(address token) internal {
        // Handle received token
        if (token == lp) {
            // - Received token is LP, deposit it into farming
            _depositToFarming();
        } else if (token == left || token == right) {
            // - Received token is pool left or right, deposit it to pair
            _depositLiquidityToPair(token);
        } else if (swaps.exists(token)) {
            // - Received token should be swapped
            _swap(token);
        }
    }

    /// @notice Receives token wallet address from the token root
    /// Only initialized tokens are allowed
    function receiveTokenWallet(
        address wallet
    ) external override {
        require(wallets.exists(msg.sender));

        wallets[msg.sender] = wallet;
    }

    /// @notice Receives booster farming user data
    /// @param _user_data Booster farming user data
    function receiveFarmingUserData(
        address _user_data
    ) external override {
        require(msg.sender == farming_pool);

        user_data = _user_data;
    }

    function _skimFees() internal {
        TvmCell empty;

        for ((address root, uint128 fee): fees) {
            if (fee == 0) continue;

            _transferTokens(
                wallets[root],
                fee,
                rewarder,
                _me(),
                false,
                empty,
                Utils.FARMING_SKIM_FEES,
                0,
                true
            );

            fees[root] = 0;
        }
    }

    function _depositLiquidityToPair(
        address token
    ) internal {
        if (balances[token] == 0) return;

        TvmCell payload = _buildDepositPayload(
            now,
            0 // Deploy wallet value = 0
        );

        _transferTokens(
            wallets[token],
            balances[token],
            pair,
            _me(),
            true,
            payload,
            Utils.DEX_DEPOSIT_LIQUIDITY,
            0,
            false
        );

        balances[token] = 0;
    }

    function _claimReward() internal view {
        IEverFarmPool(farming_pool).claimReward{
            value: Utils.FARMING_CLAIM_REWARD,
            bounce: false
        }(_me(), Utils.REINVEST_REQUIRED);
    }

    function _swap(address token) internal {
        if (balances[token] == 0) return;

        SwapDirection direction = swaps[token];

        TvmCell payload = _buildSwapPayload(
            0,
            0, // Deploy wallet value = 0
            0 // Expected amount = 0
        );

        _transferTokens(
            wallets[token],
            balances[token],
            direction.pair,
            _me(),
            true,
            payload,
            Utils.DEX_SWAP,
            0,
            false
        );

        balances[token] = 0;
    }

    function _deployTokenWallet(
        address token
    ) internal {
        balances[token] = 0;
        received[token] = 0;
        fees[token] = 0;
        wallets[token] = address.makeAddrStd(0, 0);

        ITokenRoot(token).deployWallet{
            value: Utils.DEPLOY_TOKEN_WALLET * 2,
            callback: BoosterAccountBase.receiveTokenWallet
        }(
            _me(),
            Utils.DEPLOY_TOKEN_WALLET
        );
    }

    function _depositToFarming() internal {
        if (balances[lp] == 0) return;

        TvmCell payload = _buildFarmingDepositPayload(Utils.NO_REINVEST_REQUIRED);

        _transferTokens(
            wallets[lp],
            balances[lp],
            farming_pool,
            _me(),
            true,
            payload,
            Utils.FARMING_DEPOSIT_LP,
            0,
            false
        );

        balances[lp] = 0;
    }

    /// @notice Rewards withdrawing LPs from farming to owner
    /// Can be called only by `manager` or `owner`
    /// @param amount Amount of LP to request
    function requestFarmingLP(
        uint128 amount
    ) external override onlyOwner onlyPaused reserveBalance {
        IEverFarmPool(farming_pool).withdraw{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED,
            bounce: false
        }(amount, _me(), 0);
    }

    function _requestFarmingUserData() internal view {
        IEverFarmPool(farming_pool).getUserDataAddress{
            value: Utils.FARMING_REQUEST_USER_DATA,
            bounce: false,
            callback: BoosterAccountBase.receiveFarmingUserData
        }(_me());
    }

    function _buildDepositPayload(
        uint64 id,
        uint128 deploy_wallet_grams
    ) internal pure returns(TvmCell) {
        TvmBuilder builder;
        builder.store(DexOperationTypes.DEPOSIT_LIQUIDITY);
        builder.store(id);
        builder.store(deploy_wallet_grams);

        TvmCell empty;
        builder.store(empty);

        return builder.toCell();
    }

    function _buildSwapPayload(
        uint64 id,
        uint128 deploy_wallet_grams,
        uint128 expected_amount
    ) internal pure returns(TvmCell) {
        TvmBuilder builder;
        builder.store(DexOperationTypes.EXCHANGE);
        builder.store(id);
        builder.store(deploy_wallet_grams);
        builder.store(expected_amount);

        TvmCell empty;
        builder.store(empty);

        return builder.toCell();
    }

    function _buildFarmingDepositPayload(
        uint32 nonce
    ) internal pure returns (TvmCell) {
        TvmBuilder builder;
        builder.store(_me());
        builder.store(nonce);

        return builder.toCell();
    }

    function _targetBalance() internal override pure returns(uint128) {
        return Utils.BOOSTER_DEPLOY_ACCOUNT;
    }
}
