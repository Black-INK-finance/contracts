pragma ton-solidity ^0.57.1;


import "broxus-ton-tokens-contracts/contracts/interfaces/IAcceptTokensTransferCallback.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenRoot.sol";

import "@broxus/contracts/contracts/access/InternalOwner.sol";
import "@broxus/contracts/contracts/utils/RandomNonce.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";

import "flatqube/contracts/libraries/DexOperationTypes.sol";

import "./../TransferUtils.sol";
import "./../Constants.sol";
import "./../Errors.sol";
import "./../Gas.sol";

import "../interfaces/IBoosterBuyBack.sol";


/// @notice BuyBack contract is used as a common rewarder, which receives
/// the booster fees and, if necessary, swaps them on a flatqube
contract BoosterBuyBack is
    IBoosterBuyBack,
    IAcceptTokensTransferCallback,
    InternalOwner,
    TransferUtils,
    RandomNonce
{
    mapping (address => address) public wallets;
    mapping (address => SwapDirection) public swaps;
    mapping (address => Unwrap) public unwraps;
    mapping (address => uint128) public balances;
    mapping (address => uint128) public received;

    bool public paused;

    modifier onlyMeOrOwner() {
        require(msg.sender == owner || msg.sender == _me(), Errors.WRONG_SENDER);

        _;
    }

    constructor(
        address _owner
    ) public {
        tvm.accept();

        setOwnership(_owner);
        paused = false;
    }

    /// @notice Skim gas from the factory
    /// Can be called only by `owner`
    /// @param reserve How much left on the factory
    function skimGas(
        uint128 reserve
    ) external override onlyOwner {
        tvm.rawReserve(reserve, 0);

        owner.transfer({
            value: 0,
            bounce: false,
            flag: MsgFlag.ALL_NOT_RESERVED
        });
    }

    /// @notice Pause / unpause buybacks
    /// Can be called only by `owner`
    /// @param _paused Boolean, paused / unpaused
    function setPaused(
        bool _paused
    ) external override onlyOwner cashBack(owner) {
        paused = _paused;
    }

    /// @notice Claim tokens
    /// Can be called only by `owner`
    /// @param root Token root
    function claim(
        address root,
        uint128 _amount
    ) external override reserveBalance onlyOwner {
        TvmCell empty;

        require(wallets.exists(root));

        uint128 amount = _amount;

        if (amount == 0) {
            require(balances[root] > 0);

            amount = balances[root];
        }

        _transferTokens(
            wallets[root],
            amount,
            owner,

            owner,
            false,
            empty,

            0,
            MsgFlag.ALL_NOT_RESERVED,
            true
        );

        balances[root] -= amount;
    }

    /// @notice Receives token wallet address from the token root
    /// Only initialized tokens are allowed
    function receiveTokenWallet(
        address wallet
    ) external override {
        require(wallets.exists(msg.sender));

        wallets[msg.sender] = wallet;
    }

    /// @notice Initialize token
    /// Can be called only by `owner`
    function initializeTokens(
        address[] tokens
    ) external override onlyOwner {
        for (address token: tokens) {
            if (!wallets.exists(token)) {
                _deployTokenWallet(token);
            }
        }
    }

    /// @notice Set rules for swapping received token
    /// Can be called only by `owner`
    /// @param token Token address
    /// @param swap Swap rules (pair, target token, min accumulated token to swap)
    function setTokenSwap(
        address token,
        SwapDirection swap
    ) external override onlyOwner cashBack(owner) {
        swaps[token] = swap;

        if (!wallets.exists(token)) {
            _deployTokenWallet(token);
        }

        if (!wallets.exists(swap.token)) {
            _deployTokenWallet(swap.token);
        }
    }

    function setTokenUnwrap(
        address token,
        Unwrap unwrap
    ) external override onlyOwner cashBack(owner) {
        unwraps[token] = unwrap;

        if (!wallets.exists(token)) {
            _deployTokenWallet(token);
        }
    }

    function setTokenMinToSwap(
        address token,
        uint128 amount
    ) external override onlyOwner cashBack(owner) {
        require(swaps.exists(token));

        swaps[token].minToSwap = amount;
    }

    function setTokenMinToUnwrap(
        address token,
        uint128 amount
    ) external override onlyOwner cashBack(owner) {
        require(unwraps.exists(token));

        unwraps[token].minToUnwrap = amount;
    }

    /// @notice Remove swap rules for token
    /// Can be called only by `owner`
    /// @param token Token address
    function removeTokenSwap(
        address token
    ) external override onlyOwner {
        delete swaps[token];
    }

    function removeTokenUnwrap(
        address token
    ) external override onlyOwner {
        delete unwraps[token];
    }

    function onAcceptTokensTransfer(
        address root,
        uint128 amount,
        address,
        address,
        address remainingGasTo,
        TvmCell
    ) external override cashBack(remainingGasTo) {
        // Unknown token
        if (wallets[root] != msg.sender) return;

        balances[root] += amount;
        received[root] += amount;

        if (!paused && swaps.exists(root) && balances[root] >= swaps[root].minToSwap) {
            IBoosterBuyBack(_me()).triggerSwap{
                value: 0.01 ton
            }(root);
        }

        if (!paused && unwraps.exists(root) && balances[root] >= unwraps[root].minToUnwrap) {
            IBoosterBuyBack(_me()).triggerUnwrap{
                value: 0.01 ton
            }(root);
        }
    }

    function triggerSwap(
        address token
    ) external override onlyMeOrOwner {
        tvm.accept();

        if (!paused) {
            _swap(token);
        }
    }

    function triggerUnwrap(
        address token
    ) external override onlyMeOrOwner {
        tvm.accept();

        if (!paused) {
            _unwrap(token);
        }
    }

    function _swap(address token) internal {
        if (balances[token] == 0 || !swaps.exists(token)) return;

        SwapDirection swap = swaps[token];

        if (balances[token] < swap.minToSwap) return;

        TvmCell payload = _buildSwapPayload(
            0,
            0, // Deploy wallet value = 0
            0 // Expected amount = 0
        );

        _transferTokens(
            wallets[token],
            balances[token],
            swap.pair,
            _me(),
            true,
            payload,
            Gas.BOOSTER_BUYBACK_DEX_SWAP,
            0,
            false
        );

        balances[token] = 0;
    }

    function _unwrap(address token) internal {
        if (balances[token] == 0 || !unwraps.exists(token)) return;

        Unwrap unwrap = unwraps[token];

        if (balances[token] < unwrap.minToUnwrap) return;

        TvmCell payload = _buildUnwrapPayload(0, 0);

        _transferTokens(
            wallets[token],
            balances[token],
            unwrap.pair,
            _me(),
            true,
            payload,
            Gas.BOOSTER_BUYBACK_LP_UNWRAP,
            0,
            false
        );

        balances[token] = 0;
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
            flag: flag,
            bounce: true
        }(
            amount,
            recipient,
            deploy_wallet == true ? Gas.DEPLOY_TOKEN_WALLET : 0,
            remainingGasTo,
            notify,
            payload
        );
    }

    function _deployTokenWallet(
        address token
    ) internal {
        wallets[token] = address.makeAddrStd(0, 0);

        if (!balances.exists(token)) {
            balances[token] = 0;
        }

        if (!received.exists(token)) {
            received[token] = 0;
        }

        ITokenRoot(token).deployWallet{
            value: Gas.DEPLOY_TOKEN_WALLET * 2,
            callback: BoosterBuyBack.receiveTokenWallet
        }(
            _me(),
            Gas.DEPLOY_TOKEN_WALLET
        );
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

    function _buildUnwrapPayload(
        uint64 id,
        uint128 deploy_wallet_grams
    ) internal pure returns(TvmCell) {
        TvmBuilder builder;
        builder.store(DexOperationTypes.WITHDRAW_LIQUIDITY);
        builder.store(id);
        builder.store(deploy_wallet_grams);

        TvmCell empty;
        builder.store(empty);

        return builder.toCell();
    }

    function _me() internal pure returns (address) {
        return address(this);
    }

    function upgrade(TvmCell code) external override onlyOwner {
        TvmCell data = abi.encode(
            _randomNonce,
            owner,
            wallets,
            swaps,
            balances,
            received,
            paused
        );

        tvm.setcode(code);
        tvm.setCurrentCode(code);

        onCodeUpgrade(data);
    }

    function onCodeUpgrade(TvmCell) private {}
}
