pragma ton-solidity ^0.57.1;


import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";

import "./BoosterFactoryStorage.sol";
import "./../account/BoosterAccountPlatform.sol";
import "./../passport/BoosterPassportPlatform.sol";
import "./../TransferUtils.sol";


abstract contract BoosterFactoryBase is BoosterFactoryStorage, TransferUtils {
    constructor(
        address _owner
    ) public {
        setOwnership(_owner);
    }

    modifier onlyBoosterPassport(address _owner) {
        TvmCell stateInit = _buildPassportPlatformStateInit(_owner);

        require(msg.sender == address(tvm.hash(stateInit)), Errors.WRONG_SENDER);

        _;
    }

    /// @notice Ping booster account
    /// Can be called only by booster passport
    /// @param _owner Passport owner, used for address check
    /// @param account Booster account address
    /// @param required_top_up How many EVERs needs to be sent
    function pingAccount(
        address _owner,
        uint counter,
        address account,
        uint128 price,
        uint128 required_top_up
    ) external override onlyBoosterPassport(_owner) {
        tvm.accept();

        // Top up booster
        if (required_top_up > 0) {
            msg.sender.transfer({
                value: required_top_up,
                bounce: false,
                flag: 0
            });
        }

        ping_spent += price;

        IBoosterAccount(account).ping{
            value: ping_cost,
            bounce: false,
            flag: 0
        }(counter, _me());
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
            deploy_wallet == true ? Gas.DEPLOY_TOKEN_WALLET : 0,
            remainingGasTo,
            notify,
            payload
        );
    }

    function _buildPassportPlatformStateInit(
        address _owner
    ) internal view returns(TvmCell) {
        return tvm.buildStateInit({
            contr: BoosterPassportPlatform,
            varInit: {
                factory: address(this),
                owner: _owner
            },
            pubkey: 0,
            code: passport_platform
        });
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
        address rewarder,
        uint128 reward_fee,
        uint128 lp_fee
    ) external override onlyOwner cashBack(owner) {
        require(!farmings.exists(farming_pool));
        require(lp_fee + reward_fee <= Constants.MAX_FEE);

        farmings[farming_pool] = FarmingPoolSettings({
            lp: lp,
            pair: pair,
            left: left,
            right: right,
            rewards: rewards,
            rewarder: rewarder,
            swaps: swaps,
            reward_fee: reward_fee,
            lp_fee: lp_fee
        });
    }

    /// @notice Pause / unpause farming pool
    /// Users can't create booster accounts for paused farming pools
    /// @param farming_pool Farming pool address
    function removeFarming(
        address farming_pool
    ) external override onlyOwner cashBack(owner) {
        delete farmings[farming_pool];
    }
}
