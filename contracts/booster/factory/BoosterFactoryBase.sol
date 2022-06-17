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

    /// @notice Skim gas from the factory
    /// Can be called only by `owner`
    /// @param reserve How much left on the factory
    function skimGas(
        uint128 reserve
    ) external override onlyOwner {
        tvm.rawReserve(reserve, 0);

        owner.transfer({
            value: 0,
            bounce: false,
            flag: MsgFlag.ALL_NOT_RESERVED
        });
    }

    /// @notice Ping booster account
    /// Can be called only by booster passport
    /// @param _owner Passport owner, used for address check
    /// @param account Booster account address
    /// @param required_top_up How many EVERs needs to be sent
    function pingAccount(
        address _owner,
        uint64 counter,
        address account,
        address farming_pool,
        uint128 price,
        uint128 required_top_up
    ) external override onlyBoosterPassport(_owner) {
        tvm.accept();

        // Check provided account
        TvmCell accountStateInit = _buildAccountPlatformStateInit(_owner, farming_pool);
        require(address(tvm.hash(accountStateInit)) == account, Errors.BOOSTER_FACTORY_WRONG_ACCOUNT);

        // Top up booster passport
        if (required_top_up > 0) {
            msg.sender.transfer({
                value: required_top_up,
                bounce: false,
                flag: 0
            });
        }

        ping_spent += price;

        IBoosterAccount(account).ping{
            value: farmings[farming_pool].ping_value,
            bounce: true,
            flag: 0
        }(counter);
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
        uint128 lp_fee,
        uint128 ping_value
    ) external override onlyOwner cashBack(owner) {
        require(!farmings.exists(farming_pool), Errors.BOOSTER_FACTORY_FARMING_NOT_EXISTS);
        require(lp_fee + reward_fee <= Constants.MAX_FEE, Errors.BOOSTER_FACTORY_FEE_TOO_HIGH);
        require(ping_value >= Gas.BOOSTER_FACTORY_MIN_PING_VALUE, Errors.BOOSTER_FACTORY_PING_VALUE_TOO_LOW);

        farmings[farming_pool] = FarmingPoolSettings({
            lp: lp,
            pair: pair,
            left: left,
            right: right,
            rewards: rewards,
            rewarder: rewarder,
            swaps: swaps,
            reward_fee: reward_fee,
            lp_fee: lp_fee,
            ping_value: ping_value,
            enabled: true
        });
    }

    /// @notice Set new ping value
    /// Can be called only by `owner`
    /// @param farming_pool Farming pool address
    /// @param ping_value New ping value
    function setPingValue(
        address farming_pool,
        uint128 ping_value
    ) external override onlyOwner farmingPoolExists(farming_pool) {
        require(ping_value >= Gas.BOOSTER_FACTORY_MIN_PING_VALUE, Errors.BOOSTER_FACTORY_PING_VALUE_TOO_LOW);

        farmings[farming_pool].ping_value = ping_value;
    }

    /// @notice Update manager on specific accounts
    /// Can be called only by `owner`
    /// @param passports Accounts list
    /// @param _managers List of manager public keys
    function setManagers(
        address[] passports,
        uint[] _managers,
        bool save_as_default
    ) external override cashBack(owner) onlyOwner {
        if (save_as_default) {
            managers = _managers;
        }

        for (address passport: passports) {
            IBoosterPassport(passport).setManagers{
                value: Gas.BOOSTER_FACTORY_ACCOUNT_UPDATE,
                bounce: true
            }(_managers, msg.sender);
        }
    }

    /// @notice Update reward fee on specific accounts
    /// Can be called only by `owner`
    /// @param accounts Accounts list
    /// @param lp_fee LP fee value in BPS
    /// @param reward_fee Rewards fee value in BPS
    function setFees(
        address farming_pool,
        address[] accounts,
        uint128 lp_fee,
        uint128 reward_fee,
        bool save_as_default
    ) external override cashBack(owner) onlyOwner farmingPoolExists(farming_pool) {
        require(lp_fee + reward_fee <= Constants.MAX_FEE);

        if (save_as_default) {
            farmings[farming_pool].lp_fee = lp_fee;
            farmings[farming_pool].reward_fee = reward_fee;
        }

        for (address account: accounts) {
            IBoosterAccount(account).setFees{
                value: Gas.BOOSTER_FACTORY_ACCOUNT_UPDATE,
                bounce: true
            }(lp_fee, reward_fee, msg.sender);
        }
    }

    /// @notice Skim fees on specific accounts
    /// Can be called only by `owner`
    /// @param accounts Accounts list
    function skimFees(
        address[] accounts
    ) external override onlyOwner cashBack(msg.sender) {
        for (address account: accounts) {
            IBoosterAccount(account).skim{
                value: Gas.BOOSTER_FACTORY_ACCOUNT_SKIM,
                bounce: true
            }(msg.sender);
        }
    }

    /// @notice Set rewarder address on specific accounts
    /// Can be called only by `owner`
    /// @param accounts Accounts list
    /// @param rewarder New rewarder
    function setRewarder(
        address farming_pool,
        address[] accounts,
        address rewarder,
        bool save_as_default
    ) external override cashBack(owner) onlyOwner farmingPoolExists(farming_pool) {
        if (save_as_default) {
            farmings[farming_pool].rewarder = rewarder;
        }

        /// A.K. protection
        require(rewarder != address.makeAddrStd(0, 0));

        for (address account: accounts) {
            IBoosterAccount(account).setRewarder{
                value: Gas.BOOSTER_FACTORY_ACCOUNT_UPDATE,
                bounce: true
            }(rewarder, msg.sender);
        }
    }

    /// @notice Pause / unpause farming pool
    /// Users can't create booster accounts for paused farming pools
    /// @param farming_pool Farming pool address
    function toggleFarming(
        address farming_pool
    ) external override onlyOwner farmingPoolExists(farming_pool) cashBack(owner) {
        farmings[farming_pool].enabled = !farmings[farming_pool].enabled;
    }
}
