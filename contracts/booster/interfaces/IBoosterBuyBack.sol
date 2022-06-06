pragma ton-solidity ^0.57.1;

import "./IBoosterBase.sol";


interface IBoosterBuyBack {
    struct SwapDirection {
        address token;
        address pair;
        uint128 minToSwap;
    }

    function receiveTokenWallet(
        address wallet
    ) external;

    function setTokenSwap(
        address token,
        SwapDirection swap
    ) external;

    function removeTokenSwap(
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

    function upgrade(TvmCell code) external;
}
