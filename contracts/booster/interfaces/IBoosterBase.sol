pragma ton-solidity ^0.57.1;


interface IBoosterBase {
    enum PairType { ConstantProduct, Stable }

    struct SwapDirection {
        address token;
        address pair;
        PairType pairType;
    }

    struct FarmingPoolSettings {
        address vault;
        address lp;
        address pair;
        address left;
        address right;
        address[] rewards;
        mapping (address => SwapDirection) swaps;
        address rewarder;
        uint128 reward_fee;
        uint128 lp_fee;
        uint128 ping_value;
        bool enabled;
    }
}
