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
            owner, _version, factory, farming_pool,
            last_ping, ping_counter, ping_balance, ping_price_limit,
            paused, manager, user_data,
            balances, received, wallets, fees,
            lp, pair, left, right, rewards,
            swaps, ping_frequency, rewarder, reward_fee, lp_fee
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
            uint _version,
            address _factory,
            address _farming_pool,

            uint _last_ping,
            uint _ping_counter,
            uint128 _ping_balance,
            uint128 _ping_price_limit,

            bool _paused,
            address _manager,
            address _user_data,

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
            uint256 _ping_frequency,
            address _rewarder,
            uint128 _reward_fee,
            uint128 _lp_fee
        ) = abi.decode(
            data,
            (
                address, uint, address, address,
                uint, uint, uint128, uint128,
                bool, address, address,
                mapping (address => uint128),
                mapping (address => uint128),
                mapping (address => address),
                mapping (address => uint128),
                address, address, address, address, address[],
                mapping (address => SwapDirection),
                uint256, address, uint128, uint128
            )
        );

        setOwnership(_owner);
        version = _version;
        factory = _factory;
        farming_pool = _farming_pool;

        last_ping = _last_ping;
        ping_counter = _ping_counter;
        ping_balance = _ping_balance;
        ping_price_limit = _ping_price_limit;

        paused = _paused;
        manager = _manager;
        user_data = _user_data;

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

        ping_frequency = _ping_frequency;
        rewarder = _rewarder;
        reward_fee = _reward_fee;
        lp_fee = _lp_fee;
    }
}
