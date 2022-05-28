pragma ton-solidity ^0.57.1;


import "./BoosterAccountStorage.sol";
import "./../Utils.sol";

import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";


abstract contract BoosterAccountSettings is BoosterAccountStorage {
    /// @notice Pause or unpause booster
    /// Can be called only by `owner`
    /// @param _paused New paused status
    function setPaused(
        bool _paused
    ) external override onlyOwner cashBack {
        require(_paused == !paused);

        paused = _paused;
    }

    /// @notice Set new fee value
    /// Can be called only by `factory`
    /// @param _fee New fee value in BPS
    function setFee(
        uint128 _fee
    ) external override onlyFactory cashBack {
        settings.fee = _fee;
    }

    /// @notice Withdraw tokens from the booster
    /// Can be called only by `owner`
    /// @param token Token address
    /// @param _amount Amount ot withdraw. If 0, then withdraw all virtual balance
    function withdraw(
        address token,
        uint128 _amount
    ) external override onlyOwnerOrManager tokenExists(token) {
        address wallet = tokens[token].wallet;

        uint128 amount = _amount;

        if (_amount == 0) {
            amount = tokens[token].balance;
        }

        TvmCell empty;

        _transferTokens(
            wallet,
            amount,
            owner,
            owner,
            true,
            empty,
            0,
            MsgFlag.ALL_NOT_RESERVED
        );

        tokens[token].balance -= amount;
    }

    function _transferTokens(
        address wallet,
        uint128 amount,
        address recipient,

        address remainingGasTo,
        bool notify,
        TvmCell payload,

        uint128 value,
        uint8 flag
    ) internal pure {
        ITokenWallet(wallet).transfer{
            value: value,
            flag: flag
//            bounce: false
        }(
            amount,
            recipient,
            Utils.DEPLOY_TOKEN_WALLET,
            remainingGasTo,
            notify,
            payload
        );
    }
}
