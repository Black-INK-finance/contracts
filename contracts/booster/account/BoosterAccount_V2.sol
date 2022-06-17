pragma ton-solidity ^0.57.1;


import "./../interfaces/IBoosterAccount.sol";
import "./BoosterAccountBase.sol";


contract BoosterAccount_V2 is
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
            owner, _version, factory, farming_pool, passport, user_data,
            balances, received, wallets, fees,
            lp, pair, left, right, rewards,
            swaps, rewarder, reward_fee, lp_fee
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
            address _user_data,
            bool _auto_reinvestment,

            mapping (address => uint128) _balances,
            mapping (address => uint128) _received,
            mapping (address => address) _wallets,
            mapping (address => uint128) _fees,

            address _lp,
            address _pair,
            address _left,
            address _right,
            address[] _rewards,

            mapping (address => SwapDirection) _swaps,
            address _rewarder,
            uint128 _reward_fee,
            uint128 _lp_fee
        ) = abi.decode(
            data,
            (
                address, address, address, uint,
                address, address, bool,

                mapping (address => uint128),
                mapping (address => uint128),
                mapping (address => address),
                mapping (address => uint128),
                address, address, address, address, address[],
                mapping (address => SwapDirection),
                address, uint128, uint128
            )
        );

        setOwnership(_owner);
        factory = _factory;
        farming_pool = _farming_pool;
        version = _version;

        passport = _passport;
        user_data = _user_data;
        auto_reinvestment = _auto_reinvestment;

        balances = _balances;
        received = _received;
        wallets = _wallets;
        fees = _fees;

        lp = _lp;
        pair = _pair;
        left = _left;
        right = _right;
        rewards = _rewards;

        swaps = _swaps;

        rewarder = _rewarder;
        reward_fee = _reward_fee;
        lp_fee = _lp_fee;
    }
}
