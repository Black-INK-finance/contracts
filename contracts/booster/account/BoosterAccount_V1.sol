pragma ton-solidity ^0.57.1;


import "./../interfaces/IBoosterAccount.sol";
import "./BoosterAccountBase.sol";


contract BoosterAccount_V1 is
    IBoosterAccount,
    BoosterAccountBase
{
    /// @notice Upgrade account
    /// Can be called only by `factory`
    /// Upgrade ignored if `_version` is the same as current one
    /// @param code New account code
    /// @param _version New account version
    function acceptUpgrade(
        TvmCell code,
        uint _version
    ) external override onlyFactory {
        if (version == _version) return;

        TvmCell data = abi.encode(
            owner, factory, farming_pool, _version,
            passport, user_data, auto_reinvestment,
            balances, received, wallets, fees,
            vault, lp, pair, left, right, rewards,
            swaps, pairBalancePending, pairBalances, slippage,
            rewarder, reward_fee, lp_fee
        );

        tvm.setcode(code);
        tvm.setCurrentCode(code);

        onCodeUpgrade(data);
    }

    function onCodeUpgrade(
        TvmCell data
    ) private {
        tvm.resetStorage();

        (
            address _owner,
            address _factory,
            address _farming_pool,

            uint _version,
            address _passport,
            FarmingPoolSettings settings,

            address remainingGasTo
        ) = abi.decode(
            data,
            (
                address, address, address,
                uint, address, FarmingPoolSettings,
                address
            )
        );

        setOwnership(_owner);
        factory = _factory;
        farming_pool = _farming_pool;

        version = _version;
        passport = _passport;

        auto_reinvestment = true;

        vault = settings.vault;
        lp = settings.lp;
        pair = settings.pair;
        left = settings.left;
        right = settings.right;
        rewards = settings.rewards;

        swaps = settings.swaps;

        for ((, SwapDirection swap): swaps) {
            pairBalances[swap.pair] = PairBalance(0,0);
        }
        slippage = 20;

        rewarder = settings.rewarder;
        reward_fee = settings.reward_fee;
        lp_fee = settings.lp_fee;

        _requestFarmingUserData();

        // Setup token wallets for involved tokens
        // - Pair LP
        _deployTokenWallet(lp);
        // - Pair left
        _deployTokenWallet(left);
        // - Pair right
        _deployTokenWallet(right);

        // - Farming pool rewards
        for (address reward: rewards) {
            _deployTokenWallet(reward);
        }

        // - Tokens involved in swaps
        for ((address _from, SwapDirection direction): swaps) {
            if (!wallets.exists(_from)) {
                _deployTokenWallet(_from);
            }

            if (!wallets.exists(direction.token)) {
                _deployTokenWallet(direction.token);
            }
        }

        tvm.rawReserve(_targetBalance(), 2);

        remainingGasTo.transfer({
            bounce: false,
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED
        });
    }
}
