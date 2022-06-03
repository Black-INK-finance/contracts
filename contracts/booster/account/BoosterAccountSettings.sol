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
    ) external override onlyOwner cashBack(owner) {
        require(_paused == !paused);

        paused = _paused;
    }

    /// @notice Set new manager address
    /// Can be called only by `factory`
    /// @param _manager New manager address
    function setManager(
        address _manager,
        address remainingGasTo
    ) external override onlyFactory cashBack(remainingGasTo) {
        manager = _manager;
    }

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

    /// @notice Set new ping frequency
    /// Can be called only by `owner`
    /// @param _ping_frequency New ping frequency
    function setPingFrequency(
        uint _ping_frequency
    ) external override onlyOwner cashBack(owner) {
        require(_ping_frequency >= Utils.MIN_PING_FREQUENCY);

        ping_frequency = _ping_frequency;
    }

    /// @notice Withdraw tokens from the booster
    /// Can be called only by `owner`
    /// @param token Token address
    /// @param _amount Amount ot withdraw. If 0, then withdraw all virtual balance
    function withdraw(
        address token,
        uint128 _amount
    ) external override onlyOwner tokenExists(token) {
        address wallet = wallets[token];

        uint128 amount = _amount;

        if (_amount == 0) {
            amount = balances[token];
        }

        TvmCell empty;

        _transferTokens(
            wallet,
            amount,
            owner,
            owner,
            false,
            empty,
            0,
            MsgFlag.REMAINING_GAS,
            true
        );

        balances[token] -= amount;
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
            deploy_wallet == true ? Utils.DEPLOY_TOKEN_WALLET : 0,
            remainingGasTo,
            notify,
            payload
        );
    }
}
