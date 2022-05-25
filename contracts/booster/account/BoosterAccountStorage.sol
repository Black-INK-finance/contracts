pragma ton-solidity ^0.57.1;


import "../TransferUtils.sol";
import "../interfaces/IBoosterAccount.sol";
import "@broxus/contracts/contracts/access/InternalOwner.sol";


abstract contract BoosterAccountStorage is IBoosterAccount, InternalOwner, TransferUtils {
    uint128 constant BPS  = 1_000_000;

    uint public version; // Account code version

    address public factory; // Factory
    address public farming_pool; // Farming pool

    uint public last_ping; // Last ping timestamp
    uint public ping_frequency; // How often manager should ping booster
    uint128 ping_balance; // How many tokens available as manager reward
    bool public paused; // Booster account paused flag

    address public manager; // Manager address. Can only press `ping`

    address public user_data; // Booster farming user data
    FarmingPoolSettings public settings; // Farming pool settings
    mapping (address => Token) public tokens; // Token wallets

    // === STORAGE END ===

    function _me() internal pure returns(address) {
        return address(this);
    }

    modifier tokenExists(address token) {
        require(tokens.exists(token));

        _;
    }

    modifier onlyUnpaused() {
        require(paused == false);

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
        FarmingPoolSettings _settings,
        mapping (address => Token) _tokens
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
            settings,
            tokens
        );
    }

    /// @notice Keeper method for ensuring ping is needed
    function isNeedPing() external override view returns(bool) {
        // Booster not initialized
        if (!isInitialized()) return false;

//        // Ping balance is too low
//        if (ping_balance < ping_cost) return false;

        // Not enough time passed since last ping
        if (last_ping + ping_frequency > now) return false;

        return false;
    }

    function isInitialized() public override view returns(bool) {
        bool _initialized = true;

        address zero_address = address.makeAddrStd(0, 0);

        // Token wallet for every involved token should be initialized
        for ((, Token token): tokens) {
            _initialized = _initialized && (token.wallet != zero_address);
        }

        // Booster user data should be available
        _initialized = _initialized && (user_data != zero_address);

        return _initialized;
    }
}
