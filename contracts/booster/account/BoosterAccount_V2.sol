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
            last_ping, paused, manager,
            user_data, settings, tokens
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
            bool _paused,
            address _manager,

            address _user_data,
            FarmingPoolSettings _settings,
            mapping(address => Token) _tokens
        ) = abi.decode(
            data,
            (
                address, uint, address, address,
                uint, bool, address,
                address, FarmingPoolSettings, mapping(address => Token)
            )
        );

        setOwnership(_owner);
        version = _version;
        factory = _factory;
        farming_pool = _farming_pool;

        last_ping = _last_ping;
        paused = _paused;
        manager = _manager;

        user_data = _user_data;
        settings = _settings;
        tokens = _tokens;
    }
}
