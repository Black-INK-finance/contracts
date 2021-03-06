pragma ton-solidity ^0.57.1;

import "./IBoosterBase.sol";


interface IBoosterBuyBack {
    struct SwapDirection {
        address token;
        address pair;
        uint128 minToSwap;
    }

    struct Unwrap {
        address pair;
        uint128 minToUnwrap;
    }

    function skimGas(
        uint128 reserve
    ) external;

    function receiveTokenWallet(
        address wallet
    ) external;

    function setTokenSwap(
        address token,
        SwapDirection swap
    ) external;

    function setTokenUnwrap(
        address token,
        Unwrap unwrap
    ) external;

    function setTokenMinToSwap(
        address token,
        uint128 amount
    ) external;

    function setTokenMinToUnwrap(
        address token,
        uint128 amount
    ) external;

    function removeTokenSwap(
        address token
    ) external;

    function removeTokenUnwrap(
        address token
    ) external;

    function setPaused(
        bool _paused
    ) external;

    function claim(
        address root,
        uint128 _amount
    ) external;

    function initializeTokens(
        address[] tokens
    ) external;

    function triggerSwap(
        address token
    ) external;

    function triggerUnwrap(
        address token
    ) external;

    function upgrade(TvmCell code) external;
}
