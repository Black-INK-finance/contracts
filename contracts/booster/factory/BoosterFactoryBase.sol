pragma ton-solidity ^0.57.1;


import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";

import "./BoosterFactoryStorage.sol";
import "./../account/BoosterAccountPlatform.sol";
import "./../TransferUtils.sol";
import "./../Utils.sol";


abstract contract BoosterFactoryBase is BoosterFactoryStorage, TransferUtils {
    constructor(
        address _owner
    ) public {
        setOwnership(_owner);
    }

    function _transferTokens(
        address wallet,
        uint128 amount,
        address recipient,

        address remainingGasTo,
        bool notify,
        TvmCell payload,

        uint128 value,
        uint8 flag,
        bool deploy_wallet
    ) internal pure {
        ITokenWallet(wallet).transfer{
            value: value,
            flag: flag,
            bounce: false
        }(
            amount,
            recipient,
            deploy_wallet == true ? Utils.DEPLOY_TOKEN_WALLET : 0,
            remainingGasTo,
            notify,
            payload
        );
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
    /// @param farming_pool Farming pool
    /// @param pair DEX pair address
    /// @param lp Pair LP token
    /// @param left Pair left token
    /// @param right Pair right token
    /// @param rewards Reward tokens
    /// @param swaps, (token_from => (token_to, pair))
    /// @param recommended_ping_frequency Recommended ping frequency
    /// @param rewarder Rewarder address
    /// @param reward_fee Reward fee amount in BPS
    /// @param lp_fee LP fee amount in BPS
    function addFarming(
        address farming_pool,
        address lp,
        address pair,
        address left,
        address right,
        address[] rewards,
        mapping (address => SwapDirection) swaps,
        uint recommended_ping_frequency,
        address rewarder,
        uint128 reward_fee,
        uint128 lp_fee
    ) external override onlyOwner cashBack(owner) {
        require(!farmings.exists(farming_pool));
        require(recommended_ping_frequency >= Utils.MIN_PING_FREQUENCY);
        require(lp_fee + reward_fee <= Utils.MAX_FEE);

        farmings[farming_pool] = FarmingPoolSettings({
            lp: lp,
            pair: pair,
            left: left,
            right: right,
            rewards: rewards,
            rewarder: rewarder,
            swaps: swaps,
            ping_frequency: recommended_ping_frequency,
            reward_fee: reward_fee,
            lp_fee: lp_fee,
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
    ) external override onlyOwner cashBack(owner) {
        require(farmings.exists(farming_pool));
        require(farmings[farming_pool].paused = !paused);

        farmings[farming_pool].paused = paused;
    }
}
