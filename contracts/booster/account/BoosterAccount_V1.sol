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
            address _factory,
            address _farming_pool,
            uint _version,

            address _owner,
            address _manager,
            FarmingPoolSettings _settings
        ) = abi.decode(
            data,
            (
                address, address, uint,
                address, address, FarmingPoolSettings
            )
        );

        factory = _factory;
        farming_pool = _farming_pool;
        version = _version;

        setOwnership(_owner);
        manager = _manager;
        settings = _settings;

        _requestFarmingUserData();

        // Setup token wallets for involved tokens
        // - Pair LP
        _deployTokenWallet(settings.lp);
        // - Pair left
        _deployTokenWallet(settings.left);
        // - Pair right
        _deployTokenWallet(settings.right);

        // - Farming pool rewards
        for (address reward: settings.rewards) {
            _deployTokenWallet(reward);
        }

        // - Tokens involved in swaps
        for ((address _from, SwapDirection direction): settings.swaps) {
            if (!tokens.exists(_from)) {
                _deployTokenWallet(_from);
            }

            if (!tokens.exists(direction.token)) {
                _deployTokenWallet(direction.token);
            }
        }
    }
}
