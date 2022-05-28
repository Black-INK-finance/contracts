pragma ton-solidity ^0.57.1;


import "./BoosterFactoryStorage.sol";
import "./../account/BoosterAccountPlatform.sol";
import "../TransferUtils.sol";
import "./../Utils.sol";


abstract contract BoosterFactoryBase is BoosterFactoryStorage, TransferUtils {
    constructor(
        address _owner
    ) public {
        setOwnership(_owner);
    }

    function _buildAccountPlatformStateInit(
        address _owner,
        address farming_pool
    ) internal view returns(TvmCell) {
        return tvm.buildStateInit({
            contr: BoosterAccountPlatform,
            varInit: {
                factory: address(this),
                farming_pool: farming_pool,
                owner: _owner
            },
            pubkey: 0,
            code: account_platform
        });
    }

    /// @notice Add new farming pool
    /// Can be called only by `owner`
    /// @param dex Dex root
    /// @param farming_pool Farming pool
    /// @param pair DEX pair address
    /// @param lp Pair LP token
    /// @param left Pair left token
    /// @param right Pair right token
    /// @param rewards Reward tokens
    /// @param swaps, (token_from => (token_to, pair))
    /// @param recommended_ping_frequency Recommended ping frequency
    /// @param rewarder Rewarder address
    /// @param fee Fee amount
    function addFarming(
        address dex,
        address farming_pool,
        address lp,
        address pair,
        address left,
        address right,
        address[] rewards,
        mapping (address => SwapDirection) swaps,
        uint recommended_ping_frequency,
        address rewarder,
        uint128 fee
    ) external override onlyOwner cashBack {
        require(!farmings.exists(farming_pool));
        require(recommended_ping_frequency >= Utils.MIN_PING_FREQUENCY);
        require(fee <= Utils.MAX_FEE);

        farmings[farming_pool] = FarmingPoolSettings({
            dex: dex,
            lp: lp,
            pair: pair,
            left: left,
            right: right,
            rewards: rewards,
            rewarder: rewarder,
            swaps: swaps,
            ping_frequency: recommended_ping_frequency,
            fee: fee,
            paused: false
        });
    }

    /// @notice Pause / unpause farming pool
    /// Users can't create booster accounts for paused farming pools
    /// @param farming_pool Farming pool address
    /// @param paused Paused status
    function setFarmingPaused(
        address farming_pool,
        bool paused
    ) external override onlyOwner cashBack {
        require(farmings.exists(farming_pool));
        require(farmings[farming_pool].paused = !paused);

        farmings[farming_pool].paused = paused;
    }
}
