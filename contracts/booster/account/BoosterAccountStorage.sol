pragma ton-solidity ^0.57.1;


import "../TransferUtils.sol";
import "../interfaces/IBoosterAccount.sol";
import "@broxus/contracts/contracts/access/InternalOwner.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";

import "./../Constants.sol";
import "./../Errors.sol";
import "./../Gas.sol";


abstract contract BoosterAccountStorage is IBoosterAccount, InternalOwner, TransferUtils {
    address public factory; // Factory
    address public farming_pool; // Farming pool
    uint public version; // Account code version
    address public passport; // Owner's passport
    address public user_data; // Booster farming user data
    bool public auto_reinvestment;

    // Booster token stats
    mapping (address => uint128) balances; // Token balances
    mapping (address => uint128) received; // Total token received
    mapping (address => address) wallets; // Token wallets
    mapping (address => uint128) fees; // Recorded fees

    // Farming pool settings
    address public vault; // Dex vault
    address public lp; // Farming LP
    address public pair; // Farming pair
    address public left; // Farming pair left token
    address public right; // Farming pair right token
    address[] public rewards; // Farming pool reward tokens

    mapping (address => SwapDirection) public swaps; // Swaps directions
    uint32 public pairBalancePending;
    mapping (address => PairBalance) public pairBalances; // Pair balances for pairs from swaps
    uint128 public slippage; // Preferred slippage
    address public rewarder; // Fee receiver
    uint128 public reward_fee; // Reward fee amount in BPS
    uint128 public lp_fee; // LP fee amount in BPS

    // === STORAGE END ===

    function _me() internal pure returns(address) {
        return address(this);
    }

    modifier onlyDexPair() {
        require(pairBalances.exists(msg.sender), Errors.WRONG_SENDER);
        _;
    }

    modifier tokenExists(address token) {
        require(wallets.exists(token));

        _;
    }

    modifier onlyFactory() {
        require(msg.sender == factory);

        _;
    }

    modifier onlyFactoryOrPassport() {
        require(msg.sender == factory || msg.sender == passport, Errors.WRONG_SENDER);

        _;
    }

    function encodeTokenDepositPayload(
        bool update_frequency, uint64 frequency,
        bool update_max_ping_price, uint128 max_ping_price,
        bool update_slippage, uint128 _slippage,
        bool toggle_auto_ping,
        bool toggle_auto_reinvestment
    ) external virtual pure returns(TvmCell) {
        return abi.encode(
            update_frequency, frequency,
            update_max_ping_price, max_ping_price,
            update_slippage, _slippage,
            toggle_auto_ping, toggle_auto_reinvestment
        );
    }

    function getDetails() external responsible virtual override view returns (
        address _owner,
        uint _version,
        address _factory,
        address _farming_pool,
        address _passport,
        address _user_data,
        bool _auto_reinvestment,

        mapping (address => uint128) _balances,
        mapping (address => uint128) _received,
        mapping (address => address) _wallets,
        mapping (address => uint128) _fees,

        address _vault,
        address _lp,
        address _pair,
        address _left,
        address _right,
        address[] _rewards,

        mapping (address => SwapDirection) _swaps,
        uint32 _pairBalancePending,
        mapping (address => PairBalance) _pairBalances,
        uint128 _slippage,
        address _rewarder,
        uint128 _reward_fee,
        uint128 _lp_fee
    ) {
        return {value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS}(
            owner,
            version,
            factory,
            farming_pool,
            passport,
            user_data,
            auto_reinvestment,

            balances,
            received,
            wallets,
            fees,

            vault,
            lp,
            pair,
            left,
            right,
            rewards,

            swaps,
            pairBalancePending,
            pairBalances,
            slippage,
            rewarder,
            reward_fee,
            lp_fee
        );
    }

    function isInitialized() public override virtual view returns(bool) {
        bool _initialized = true;

        address zero_address = address.makeAddrStd(0, 0);

        // Token wallet for every involved token should be initialized
        for ((, address wallet): wallets) {
            _initialized = _initialized && (wallet != zero_address);
        }

        // Booster user data should be available
        _initialized = _initialized && (user_data != zero_address);

        return _initialized;
    }

    function _isArrayIncludes(address target, address[] elements) internal pure returns(bool) {
        for (address element: elements) {
            if (target == element) return true;
        }

        return false;
    }
}
