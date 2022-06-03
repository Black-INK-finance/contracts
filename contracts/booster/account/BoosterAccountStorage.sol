pragma ton-solidity ^0.57.1;


import "../TransferUtils.sol";
import "../interfaces/IBoosterAccount.sol";
import "@broxus/contracts/contracts/access/InternalOwner.sol";


abstract contract BoosterAccountStorage is IBoosterAccount, InternalOwner, TransferUtils {
    uint public version; // Account code version
    address public factory; // Factory
    address public farming_pool; // Farming pool

    uint public last_ping; // Last time ping was called, timestamp
    uint public ping_counter; // Ping calls counter
    uint128 public ping_balance; // How many ping tokens booster has
    uint128 public ping_price_limit; // Max price of ping in ping tokens

    bool public paused; // Booster account paused flag
    address public manager; // Manager address. Can only press `ping`
    address public user_data; // Booster farming user data

    // Booster token stats
    mapping (address => uint128) balances; // Token balances
    mapping (address => uint128) received; // Total token received
    mapping (address => address) wallets; // Token wallets
    mapping (address => uint128) fees; // Recorded fees

    // Farming pool settings
    address lp; // Farming LP
    address pair; // Farming pair
    address left; // Farming pair left token
    address right; // Farming pair right token
    address[] rewards; // Farming pool reward tokens
    mapping (address => SwapDirection) swaps; // Swaps directions
    uint256 ping_frequency; // Desired ping frequency
    address rewarder; // Fee receiver
    uint128 reward_fee; // Reward fee amount in BPS
    uint128 lp_fee; // LP fee amount in BPS

    // === STORAGE END ===

    function _me() internal pure returns(address) {
        return address(this);
    }

    modifier tokenExists(address token) {
        require(wallets.exists(token));

        _;
    }

    modifier onlyUnpaused() {
        require(paused == false);

        _;
    }

    modifier onlyPaused() {
        require(paused == true);

        _;
    }

    modifier onlyFactory() {
        require(msg.sender == factory);

        _;
    }

    modifier onlyManager() {
        require(msg.sender == manager);

        _;
    }

    modifier onlyOwnerOrManager() {
        require(msg.sender == manager || msg.sender == owner);

        _;
    }

    function getDetails() external override view returns (
        address _owner,
        uint _version,
        address _factory,
        address _farming_pool,

        uint _last_ping,
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
    ) {
        return (
            owner,
            version,
            factory,
            farming_pool,

            last_ping,
            paused,
            manager,
            user_data,

            balances,
            received,
            wallets,
            fees,

            lp,
            pair,
            left,
            right,
            rewards,

            swaps,
            ping_frequency,
            rewarder,
            reward_fee,
            lp_fee
        );
    }

    /// @notice Keeper method for ensuring ping is needed
    function isNeedPing(uint128 ping_price) external override view returns(bool) {
        // Booster not initialized
        if (!isInitialized()) return false;

        // Ping balance is too low
        if (ping_balance < ping_price) return false;

        // Not enough time passed since last ping
        if (last_ping + ping_frequency > now) return false;

        return true;
    }

    function isInitialized() public override view returns(bool) {
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
