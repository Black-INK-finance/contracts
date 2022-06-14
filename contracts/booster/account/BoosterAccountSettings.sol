pragma ton-solidity ^0.57.1;


import "./BoosterAccountStorage.sol";

import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";


abstract contract BoosterAccountSettings is BoosterAccountStorage {
    /// @notice Set reward fee in BPS
    /// Can be called only by `factory`
    /// @param fee Reward fee in BPS
    function setRewardFee(
        uint128 fee,
        address remainingGasTo
    ) external override onlyFactory cashBack(remainingGasTo) {
        reward_fee = fee;
    }

    /// @notice Set LP fee in BPS
    /// Can be called only by `factory`
    /// @param fee LP fee in BPS
    function setLpFee(
        uint128 fee,
        address remainingGasTo
    ) external override onlyFactory cashBack(remainingGasTo) {
        lp_fee = fee;
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
