pragma ton-solidity ^0.57.1;


import "@broxus/contracts/contracts/libraries/MsgFlag.sol";

import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenRoot.sol";

import "flatqube/contracts/interfaces/IDexRoot.sol";
import "flatqube/contracts/interfaces/IDexAccount.sol";
import "flatqube/contracts/libraries/DexOperationTypes.sol";

import "./../../v3/interfaces/IEverFarmPool.sol";

import "./BoosterAccountSettings.sol";
import "./../Utils.sol";


abstract contract BoosterAccountBase is InternalOwner, BoosterAccountSettings {
    /// @notice Receives token wallet address from the token root
    /// Only initialized tokens are allowed
    function receiveTokenWallet(
        address wallet
    ) external override {
        require(tokens.exists(msg.sender));

        tokens[msg.sender].wallet = wallet;
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

        for ((address root, Token token): tokens) {
            if (token.fee == 0) continue;

            _transferTokens(
                token.wallet,
                token.fee,
                settings.rewarder,
                _me(),
                false,
                empty,
                Utils.FARMING_SKIM_FEES,
                0
            );

            tokens[root].fee = 0;
        }
    }

    function _depositLiquidityToPair(
        address token
    ) internal {
        if (tokens[token].balance == 0) return;

        TvmCell payload = _buildDepositPayload(
            now,
            0 // Deploy wallet value = 0
        );

        _transferTokens(
            tokens[token].wallet,
            tokens[token].balance,
            settings.pair,
            _me(),
            true,
            payload,
            Utils.DEX_DEPOSIT_LIQUIDITY,
            0
        );

        tokens[token].balance = 0;
    }

    function _claimReward() internal view {
        IEverFarmPool(farming_pool).claimReward{
            value: Utils.FARMING_CLAIM_REWARD,
            bounce: false
        }(_me(), REINVEST_REQUIRED);
    }

    function _swap(address token) internal {
        if (tokens[token].balance == 0) return;

        SwapDirection direction = settings.swaps[token];

        TvmCell payload = _buildSwapPayload(
            uint64(tokens[token].balance),
            0, // Deploy wallet value = 0
            0 // Expected amount = 0
        );

        _transferTokens(
            tokens[token].wallet,
            tokens[token].balance,
            direction.pair,
            _me(),
            true,
            payload,
            Utils.DEX_SWAP,
            0
        );

        tokens[token].balance = 0;
    }

    function _deployTokenWallet(
        address token
    ) internal {
        tokens[token] = Token({
            balance: 0,
            received: 0,
            fee: 0,
            wallet: address.makeAddrStd(0, 0)
        });

        ITokenRoot(token).deployWallet{
            value: Utils.DEPLOY_TOKEN_WALLET * 2,
            callback: BoosterAccountBase.receiveTokenWallet
        }(
            _me(),
            Utils.DEPLOY_TOKEN_WALLET
        );
    }

    function _depositToFarming() internal {
        if (tokens[settings.lp].balance == 0) return;

        TvmCell payload = _buildFarmingDepositPayload(NO_REINVEST_REQUIRED);

        _transferTokens(
            tokens[settings.lp].wallet,
            tokens[settings.lp].balance,
            farming_pool,
            _me(),
            true,
            payload,
            Utils.FARMING_DEPOSIT_LP,
            0
        );

        tokens[settings.lp].balance = 0;
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
