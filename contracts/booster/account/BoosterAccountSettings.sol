pragma ton-solidity ^0.57.1;


import "./BoosterAccountStorage.sol";

import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";


abstract contract BoosterAccountSettings is BoosterAccountStorage {
    /// @notice Set LP and reward fee in BPS
    /// Can be called only by `factory`
    function setFees(
        uint128 _lp_fee,
        uint128 _reward_fee,
        address remainingGasTo
    ) external override onlyFactory cashBack(remainingGasTo) {
        lp_fee = _lp_fee;
        reward_fee = _reward_fee;
    }

    /// @notice Set new rewarder
    /// Can be called only by `factory`
    /// @param _rewarder New rewarder
    function setRewarder(
        address _rewarder,
        address remainingGasTo
    ) external override onlyFactory cashBack(remainingGasTo) {
        rewarder = _rewarder;
    }

    /// @notice Toggle token processing
    /// If disabled, than all received tokens will be immediately sent to owner
    /// Can be called only by `owner`
    function toggleTokenProcessing() external override onlyOwner cashBack(owner) {
        token_processing = !token_processing;
    }

    function _transferTokens(
        address wallet,
        uint128 amount,
        address recipient,

        address remainingGasTo,
        bool notify,
        TvmCell payload,

        uint128 value,
        uint8 flag,
        bool deploy_wallet
    ) internal pure {
        ITokenWallet(wallet).transfer{
            value: value,
            flag: flag
//            bounce: false
        }(
            amount,
            recipient,
            deploy_wallet == true ? Gas.DEPLOY_TOKEN_WALLET : 0,
            remainingGasTo,
            notify,
            payload
        );
    }
}
