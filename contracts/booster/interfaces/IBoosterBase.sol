pragma ton-solidity ^0.57.1;


interface IBoosterBase {
    struct SwapDirection {
        address token;
        address pair;
    }

    struct FarmingPoolSettings {
        address dex;
        address lp;
        address pair;
        address left;
        address right;
        address[] rewards;
        mapping (address => SwapDirection) swaps;
//        uint128 ping_cost;
        uint256 ping_frequency;
        address rewarder;
        uint128 fee;
        bool paused;
    }
}
