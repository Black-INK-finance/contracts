pragma ton-solidity ^0.57.1;


import "@broxus/contracts/contracts/libraries/MsgFlag.sol";

import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/IAcceptTokensTransferCallback.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/IAcceptTokensMintCallback.sol";

import {
    IDexPair
} from "flatqube/contracts/interfaces/IDexPair.sol";
import "flatqube/contracts/interfaces/IDexRoot.sol";
import "flatqube/contracts/interfaces/IDexAccount.sol";
import "flatqube/contracts/libraries/DexOperationTypes.sol";

import "./../interfaces/IBoosterPassport.sol";
import "./../../v3/interfaces/IEverFarmPool.sol";

import "./BoosterAccountSettings.sol";
import "./../Constants.sol";


abstract contract BoosterAccountBase is
    IAcceptTokensTransferCallback,
    IAcceptTokensMintCallback,
    BoosterAccountSettings
{
    constructor() public {
        revert();
    }

    /// @notice Keeper method for claiming farming reward
    /// Can be called only by `passport` or `factory`
    /// @param counter Current ping order number
    function ping(
        uint64 counter
    ) external override {
        require(msg.sender == passport || msg.sender == factory, Errors.WRONG_SENDER);

        // Automatically skim gas to owner
        // After balance exceeds some constant
        if (address(this).balance > _targetBalance() + Gas.BOOSTER_ACCOUNT_EXCEEDING_GAS_LIMIT) {
            owner.transfer({
                flag: 0,
                bounce: false,
                value: address(this).balance - _targetBalance()
            });
        }

        if (counter % Constants.PINGS_PER_SKIM == 0) {
            _skimFees(_me());
        }

        _loadDexRates();
    }

    function _loadDexRates() internal {
        pairBalancePending = 0;

        for ((, SwapDirection swap): swaps) {
            pairBalancePending++;

            IDexPair(swap.pair).getBalances{
                value: Gas.BOOSTER_ACCOUNT_REQUEST_DEX_PAIR_BALANCES,
                bounce: false,
                callback: BoosterAccountBase.receiveDexPairBalances
            }();
        }

        // No swaps are involved
        if (pairBalancePending == 0) {
            _claimReward();
        }
    }

    function receiveDexPairBalances(
        IDexPair.IDexPairBalances balances
    ) external override onlyDexPair {
        pairBalances[msg.sender].left = balances.left_balance;
        pairBalances[msg.sender].right = balances.right_balance;

        pairBalancePending--;

        if (pairBalancePending == 0) {
            // Rates for involved pairs are discovered, claim fees
            _claimReward();
        }
    }

    /// @notice Keeper method for skimming fees
    /// Can be called only by `factory`
    function skim(
        address remainingGasTo
    ) external override onlyFactory cashBack(remainingGasTo) {
        _skimFees(remainingGasTo);
    }

    /// @notice Skim gas from the booster account
    /// Can be called only by `owner`
    function skimGas() external override onlyOwner {
        tvm.rawReserve(_targetBalance(), 0);

        owner.transfer({
            value: 0,
            bounce: false,
            flag: MsgFlag.ALL_NOT_RESERVED
        });
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
        address remainingGasTo,
        TvmCell payload
    ) external virtual override {
        bool unknown_token = (!wallets.exists(root) || msg.sender != wallets[root]);
        bool lp_withdraw = (root == lp && sender == farming_pool);
        bool claim_with_no_reinvest = (auto_reinvestment == false && sender == farming_pool);

        // Received unknown token, return back with all remaining gas
        // - Or received LP from farming pool, which means user requested LP withdraw
        // - Or tokens processing is disabled
        if (unknown_token || lp_withdraw || claim_with_no_reinvest) {
            TvmCell empty;

            emit AccountTokensSentToOwner(root, sender, amount);

            _transferTokens(
                msg.sender,
                amount,
                owner,

                remainingGasTo,
                false,
                empty,

                0,
                MsgFlag.REMAINING_GAS,
                true
            );

            return;
        }

        emit AccountReceivedTokensTransfer(root, amount, sender);

        // Owner can change account / passport settings at the time of sending tokens
        if (sender == owner) {
            _updateSettings(payload);
        }

        // Consider reward fees in case they are sent from the farming pool
        if (_isArrayIncludes(root, rewards) && sender == farming_pool) {
            // Get management fees from reward, which are sent from the farming pool
            uint128 fee = math.muldivr(amount, reward_fee, Constants.BPS);

            // Consider fees
            _considerTokensFee(root, fee);
            _considerTokensArrival(root, amount - fee);

            emit AccountGainedReward(root, amount, fee);

            if (fee == amount) return;

            // Check reward transfer payload
            (uint32 nonce) = abi.decode(payload, (uint32));

            if (nonce == Constants.NO_REINVEST_REQUIRED) {
                return;
            }

            _processTokensArrival(root, _me(), true);
        } else {
            _considerTokensArrival(root, amount);

            // In case tokens are sent from vault or pair
            if (sender == vault || pairBalances.exists(sender)) {
                (bool succeeded, bool gained) = abi.decode(payload, (bool, bool));

                // For some reason swap / lp deposit failed, try on next ping
                if (!succeeded) return;

                _processTokensArrival(root, _me(), gained);
            }

            _processTokensArrival(root, _me(), false);
        }
    }

    /// @notice Accepts tokens mint
    /// Only few tokens are acceptable, any other token will be sent to the owner
    /// @param root Transferred token root
    /// @param amount Transfer amount
    function onAcceptTokensMint(
        address root,
        uint128 amount,
        address,
        TvmCell payload
    ) external virtual override {
        // Unknown token or auto reinvestment disabled
        if (!wallets.exists(root) || wallets[root] != msg.sender) {
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

        emit AccountReceivedTokensMint(root, amount);

        // Account received some minted LPs
        if (root == lp) {
            // See if minted LPs can be traced back to the rewards
            (bool succeeded, bool gained) = abi.decode(payload, (bool, bool));

            if (gained) {
                // Get management fees from LP
                uint128 fee = math.muldivr(amount, lp_fee, Constants.BPS);

                _considerTokensFee(lp, fee);
                _considerTokensArrival(lp, amount - fee);

                emit AccountGainedLp(amount, fee);

                if (fee == amount) return;
            } else {
                // Eg LPs are produced from left tokens
                // which owner sent to the account as a deposit
                // dont charge this operations
                _considerTokensArrival(root, amount);
            }

            if (!succeeded) return;

            _processTokensArrival(root, _me(), gained);
        } else {
            _considerTokensArrival(root, amount);

            _processTokensArrival(root, _me(), false);
        }
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

    function _processTokensArrival(
        address token,
        address remainingGasTo,
        bool gained
    ) internal {
        // Handle received token
        if (token == lp) {
            // - Received token is LP, deposit it into farming
            _depositToFarming(remainingGasTo);
        } else if (token == left || token == right) {
            // - Received token is pool left or right, deposit it to pair
            _depositLiquidityToPair(token, gained);
        } else if (swaps.exists(token)) {
            // - Received token should be swapped
            _swap(token, gained);
        }
    }

    /// @notice Receives booster farming user data
    /// @param _user_data Booster farming user data
    function receiveFarmingUserData(
        address _user_data
    ) external override {
        require(msg.sender == farming_pool, Errors.WRONG_SENDER);

        user_data = _user_data;
    }

    function _skimFees(address remainingGasTo) internal {
        TvmCell empty;

        for ((address root, uint128 fee): fees) {
            if (fee == 0) continue;

            _transferTokens(
                wallets[root],
                fee,
                rewarder,

                remainingGasTo,
                true,
                empty,

                Gas.BOOSTER_ACCOUNT_TRANSFER_FEES,
                0,
                true
            );

            fees[root] = 0;
        }
    }

    function _depositLiquidityToPair(
        address token,
        bool gained
    ) internal {
        if (balances[token] == 0) return;

        TvmCell payload = _buildDepositPayload(
            now,
            0, // Deploy wallet value = 0
            gained
        );

        _transferTokens(
            wallets[token],
            balances[token],
            pair,
            _me(),
            true,
            payload,
            Gas.BOOSTER_ACCOUNT_DEPOSIT_TOKEN_TO_DEX,
            0,
            false
        );

        balances[token] = 0;
    }

    function _claimReward() internal view {
        IEverFarmPool(farming_pool).claimReward{
            value: Gas.FARMING_CLAIM_REWARD,
            bounce: false
        }(_me(), Constants.REINVEST_REQUIRED);
    }

    function _swap(
        address token,
        bool gained
    ) internal {
        if (balances[token] == 0) return;

        uint128 amount = balances[token];

        SwapDirection direction = swaps[token];

        uint128 expectedAmount = _getExpectedAmount(token, direction, amount);

        TvmCell payload = _buildSwapPayload(
            0,
            0, // Deploy wallet value = 0
            expectedAmount,
            gained
        );

        emit AccountSwap(token, direction.token, expectedAmount, gained);

        _transferTokens(
            wallets[token],
            amount,
            direction.pair,
            _me(),
            true,
            payload,
            Gas.BOOSTER_ACCOUNT_DEX_SWAP,
            0,
            false
        );

        balances[token] = 0;
    }

    function _getExpectedAmount(
        address token,
        SwapDirection direction,
        uint128 amount
    ) internal view returns(uint128) {
        uint128 exactExpectedAmount;

        if (direction.pairType == PairType.Stable) {
            exactExpectedAmount = amount;
        } else {
            PairBalance balance = pairBalances[direction.pair];

            if (balance.left == 0 || balance.right == 0) return 0;

            if (token.value < direction.token.value) {
                // Sent token is left
                exactExpectedAmount = math.muldiv(amount, balance.right, balance.left);
            } else {
                // Received token is left
                exactExpectedAmount = math.muldiv(amount, balance.left, balance.right);
            }
        }

        // Consider slippage
        return math.muldiv(exactExpectedAmount, Constants.BPS - slippage, Constants.BPS);
    }

    function _depositToFarming(address remainingGasTo) internal {
        if (balances[lp] == 0) return;

        TvmCell payload = _buildFarmingDepositPayload(Constants.NO_REINVEST_REQUIRED);

        _transferTokens(
            wallets[lp],
            balances[lp],
            farming_pool,
            remainingGasTo,
            true,
            payload,
            Gas.BOOSTER_ACCOUNT_DEPOSIT_LP_TO_FARMING,
            0,
            false
        );

        balances[lp] = 0;
    }

    /// @notice Rewards withdrawing LPs from farming to owner
    /// Can be called only by `owner`
    /// @param amount Amount of LP to request
    /// @param toggle_auto_reinvestment Toggle auto reinvestment
    function requestFarmingLP(
        uint128 amount,
        bool toggle_auto_reinvestment
    ) external override onlyOwner reserveBalance {
        if (toggle_auto_reinvestment) {
            _toggleAutoReinvestment();
        }

        IEverFarmPool(farming_pool).withdraw{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED,
            bounce: true
        }(amount, msg.sender, Constants.NO_REINVEST_REQUIRED);
    }

    function _requestFarmingUserData() internal view {
        IEverFarmPool(farming_pool).getUserDataAddress{
            value: Gas.FARMING_REQUEST_USER_DATA,
            bounce: false,
            callback: BoosterAccountBase.receiveFarmingUserData
        }(_me());
    }

    function _buildDepositPayload(
        uint64 id,
        uint128 deploy_wallet_grams,
        bool gained
    ) internal pure returns(TvmCell) {
        TvmBuilder builder;
        builder.store(DexOperationTypes.DEPOSIT_LIQUIDITY);
        builder.store(id);
        builder.store(deploy_wallet_grams);

        TvmCell success = abi.encode(true, gained);
        builder.store(success);

        TvmCell cancel = abi.encode(false, gained);
        builder.store(cancel);

        return builder.toCell();
    }

    function _buildSwapPayload(
        uint64 id,
        uint128 deploy_wallet_grams,
        uint128 expected_amount,
        bool gained
    ) internal pure returns(TvmCell) {
        TvmBuilder builder;
        builder.store(DexOperationTypes.EXCHANGE);
        builder.store(id);
        builder.store(deploy_wallet_grams);
        builder.store(expected_amount);

        TvmCell success = abi.encode(true, gained);
        builder.store(success);

        TvmCell cancel = abi.encode(false, gained);
        builder.store(cancel);

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
        return Gas.BOOSTER_ACCOUNT_TARGET_BALANCE;
    }
}
