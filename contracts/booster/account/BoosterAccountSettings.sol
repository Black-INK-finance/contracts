pragma ton-solidity ^0.57.1;


import "./BoosterAccountStorage.sol";

import "./../interfaces/IBoosterPassport.sol";

import "@broxus/contracts/contracts/libraries/MsgFlag.sol";

import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenRoot.sol";


abstract contract BoosterAccountSettings is BoosterAccountStorage {
    /// @notice Receives token wallet address from the token root
    /// Only initialized tokens are allowed
    function receiveTokenWallet(
        address wallet
    ) external override {
        require(wallets.exists(msg.sender), Errors.WRONG_SENDER);

        wallets[msg.sender] = wallet;

        tvm.rawReserve(_targetBalance(), 0);

        owner.transfer({
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED,
            bounce: false
        });
    }

    /// @notice Set LP and reward fee in BPS
    /// Can be called only by `factory`
    function setFees(
        uint128 _lp_fee,
        uint128 _reward_fee,
        address remainingGasTo
    ) external virtual override onlyFactory cashBack(remainingGasTo) {
        lp_fee = _lp_fee;
        reward_fee = _reward_fee;
    }

    /// @notice Set new rewarder
    /// Can be called only by `factory`
    /// @param _rewarder New rewarder
    function setRewarder(
        address _rewarder,
        address remainingGasTo
    ) external virtual override onlyFactory cashBack(remainingGasTo) {
        rewarder = _rewarder;
    }

    function setSwaps(
        mapping (address => SwapDirection) _swaps,
        address remainingGasTo
    ) external override virtual onlyFactory cashBack(remainingGasTo) {
        swaps = _swaps;

        for ((, SwapDirection swap): swaps) {
            pairBalances[swap.pair] = PairBalance(0,0);
        }

        for ((address _from, SwapDirection direction): swaps) {
            if (!wallets.exists(_from)) {
                _deployTokenWallet(_from);
            }

            if (!wallets.exists(direction.token)) {
                _deployTokenWallet(direction.token);
            }
        }
    }

    /// @notice Toggle token auto reinvestment
    /// If disabled, than all received rewards will be immediately sent to owner
    /// If enabled, than rewards will
    /// Can be called only by `owner`
    function toggleAutoReinvestment() external virtual override onlyOwner cashBack(owner) {
        _toggleAutoReinvestment();
    }

    /// @notice Update swaps slippage
    /// Can be called only by owner
    /// @param _slippage New slippage value
    function updateSlippage(
        uint128 _slippage
    ) external override onlyOwner cashBack(owner) {
        require(slippage >= Constants.MIN_SLIPPAGE, Errors.BOOSTER_ACCOUNT_SLIPPAGE_TOO_LOW);

        _updateSlippage(_slippage);
    }

    function updateSettings(TvmCell settings) external override virtual onlyOwner cashBack(owner) {
        _updateSettings(settings);
    }

    function _updateSettings(TvmCell settings) internal {
        (
            bool update_frequency, uint64 frequency,
            bool update_max_ping_price, uint128 max_ping_price,
            bool update_slippage, uint128 _slippage,
            bool toggle_auto_ping,
            bool toggle_auto_reinvestment
        ) = abi.decode(settings, (bool, uint64, bool, uint128, bool, uint128, bool, bool));

        if (update_frequency && frequency > 0) {
            IBoosterPassport(passport).setPingFrequency{
                bounce: true,
                flag: 0,
                value: Gas.BOOSTER_FACTORY_PASSPORT_UPDATE
            }(_me(), frequency);
        }

        if (update_max_ping_price && max_ping_price > 0) {
            IBoosterPassport(passport).setPingMaxPrice{
                bounce: true,
                flag: 0,
                value: Gas.BOOSTER_FACTORY_PASSPORT_UPDATE
            }(max_ping_price);
        }

        if (update_slippage && _slippage >= Constants.MIN_SLIPPAGE) {
            _updateSlippage(_slippage);
        }

        if (toggle_auto_ping) {
            IBoosterPassport(passport).toggleAccountAutoPing{
                bounce: true,
                flag: 0,
                value: Gas.BOOSTER_FACTORY_PASSPORT_UPDATE
            }(_me());
        }

        if (toggle_auto_reinvestment) {
            _toggleAutoReinvestment();
        }
    }

    function _updateSlippage(
        uint128 _slippage
    ) internal {
        slippage = _slippage;

        emit SlippageUpdated(slippage);
    }

    function _toggleAutoReinvestment() internal {
        auto_reinvestment = !auto_reinvestment;

        emit AutoReinvestmentUpdated(auto_reinvestment);
    }

    function _deployTokenWallet(
        address token
    ) internal {
        balances[token] = 0;
        received[token] = 0;
        fees[token] = 0;
        wallets[token] = address.makeAddrStd(0, 0);

        ITokenRoot(token).deployWallet{
            value: Gas.DEPLOY_TOKEN_WALLET * 2,
            callback: BoosterAccountSettings.receiveTokenWallet
        }(
            _me(),
            Gas.DEPLOY_TOKEN_WALLET
        );
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
