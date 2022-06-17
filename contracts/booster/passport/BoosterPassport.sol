pragma ton-solidity ^0.57.1;
pragma AbiHeader time;
pragma AbiHeader pubkey;
pragma AbiHeader expire;


import "./../TransferUtils.sol";
import "./../Constants.sol";
import "./../Errors.sol";
import "./../Gas.sol";

import "./../interfaces/IBoosterPassport.sol";
import "./../interfaces/IBoosterAccount.sol";
import "./../interfaces/IBoosterFactory.sol";

import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "@broxus/contracts/contracts/access/InternalOwner.sol";


contract BoosterPassport is TransferUtils, IBoosterPassport, InternalOwner {
    address public factory;
    uint public version;
    uint[] public managers;
    uint128 public ping_balance;
    uint128 public ping_max_price;
    mapping (address => AccountSettings) public accounts;

    constructor() public {
        revert();
    }

    modifier accountExists(address account) {
        require(accounts.exists(account), Errors.BOOSTER_PASSPORT_ACCOUNT_NOT_EXISTS);

        _;
    }

    modifier onlyManager() {
        require(_isArrayIncludes(msg.pubkey(), managers), Errors.WRONG_SENDER);

        _;
    }

    modifier onlyOwnerOrAccount(address account) {
        require(msg.sender == owner || msg.sender == account, Errors.WRONG_SENDER);

        _;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, Errors.WRONG_SENDER);

        _;
    }

    function onCodeUpgrade(TvmCell data) private {
        tvm.resetStorage();

        (
            address _factory,
            address _owner,
            uint _version,
            uint[] _managers,
            uint128 _ping_max_price,
            address remainingGasTo
        ) = abi.decode(
            data,
            (
                address, address, uint,
                uint[], uint128, address
            )
        );

        tvm.rawReserve(_targetBalance(), 2);

        factory = _factory;
        setOwnership(_owner);
        version = _version;
        managers = _managers;
        ping_max_price = _ping_max_price;

        remainingGasTo.transfer({
            bounce: false,
            flag: MsgFlag.ALL_NOT_RESERVED,
            value: 0
        });
    }

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
            owner, factory, _version, managers,
            ping_balance, ping_max_price, accounts
        );

        tvm.setcode(code);
        tvm.setCurrentCode(code);

        onCodeUpgrade(data);
    }

    /// @notice Accept ping token top up
    /// Can be called only by `factory`
    /// @param amount Amount of ping tokens to accept
    function acceptPingTokens(
        uint128 amount,
        address remainingGasTo
    ) external override onlyFactory cashBack(remainingGasTo) {
        emit PingTokensAccepted(amount);

        ping_balance += amount;
    }

    /// @notice Withdraw ping tokens. Decreases ping balance, tokens are actually withdrawn from the factory.
    /// Can be called only by `owner`
    /// @param amount Amount of ping tokens to withdraw
    function withdrawPingToken(
        uint128 amount,
        address remainingGasTo
    ) external override onlyOwner reserveBalance {
        require(amount >= ping_balance);

        ping_balance -= amount;

        emit PingTokensWithdrawn(amount);

        IBoosterFactory(factory).withdrawPingTokens{
            value: 0,
            bounce: true,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(owner, amount, remainingGasTo);
    }

    /// @notice Set ping frequency
    /// Can be called only by `owner`
    /// @param account Booster account address
    /// @param frequency New ping frequency
    function setPingFrequency(
        address account,
        uint128 frequency
    ) external override onlyOwnerOrAccount(account) accountExists(account) cashBack(msg.sender) {
        require(frequency >= Constants.MIN_PING_FREQUENCY, Errors.BOOSTER_PASSPORT_PING_FREQUENCY_TOO_LOW);

        accounts[account].ping_frequency = frequency;

        emit PingFrequencyUpdated(account, frequency);
    }

    /// @notice Set ping max price
    /// Can be called only by `owner`
    /// @param price New ping max price
    function setPingMaxPrice(
        uint128 price
    ) external override onlyOwner cashBack(msg.sender) {
        ping_max_price = price;

        emit PingMaxPriceUpdated(ping_max_price);
    }

    /// @notice Set manager keys, authorized to call `pingByManager`
    /// Can be called only by `factory`
    /// @param _managers List of manager keys
    function setManagers(
        uint[] _managers,
        address remainingGasTo
    ) external override onlyFactory cashBack(remainingGasTo) {
        managers = _managers;

        emit ManagersUpdated(managers);
    }

    function registerAccount(
        address account,
        address farming_pool,
        uint128 ping_frequency,
        address remainingGasTo
    ) external override onlyFactory cashBack(remainingGasTo) {
        require(!accounts.exists(account), Errors.BOOSTER_PASSPORT_ACCOUNT_ALREADY_REGISTERED);

        accounts[account] = AccountSettings({
            ping_frequency: ping_frequency,
            farming_pool: farming_pool,
            last_ping: 0,
            ping_counter: 0,
            auto_ping_enabled: true
        });

        emit AccountRegistered(account);
        emit AutoPingUpdated(account, true);
        emit PingFrequencyUpdated(account, ping_frequency);
    }

    /// @notice Toggle account auto ping
    /// Can be called only by `owner`
    /// @param account Booster account address
    function toggleAccountAutoPing(
        address account
    ) external override onlyOwnerOrAccount(account) accountExists(account) cashBack(msg.sender) {
        accounts[account].auto_ping_enabled = !accounts[account].auto_ping_enabled;

        emit AutoPingUpdated(account, accounts[account].auto_ping_enabled);
    }

    /// @notice Initialize ping
    /// Can be called
    /// - by manager with external in message
    /// - by owner with internal message
    /// @param price Ping price
    /// @param account Booster account
    /// @param counter Account pings counter, used to prevent double-calling by multiple pings
    function pingByManager(
        uint128 price,
        address account,
        uint counter
    ) external override onlyManager accountExists(account) {
        // - Manager uses external in message, passport pays itself
        tvm.accept();

        AccountSettings settings = accounts[account];

        require(ping_balance >= price, Errors.BOOSTER_PASSPORT_PING_BALANCE_TOO_LOW);
        require(settings.ping_counter == counter, Errors.BOOSTER_PASSPORT_WRONG_COUNTER);
        require(ping_max_price >= price, Errors.BOOSTER_PASSPORT_PRICE_TOO_HIGH);
        require(settings.auto_ping_enabled, Errors.BOOSTER_PASSPORT_AUTO_PING_DISABLED);
        require(settings.last_ping + settings.ping_frequency <= now, Errors.BOOSTER_PASSPORT_PING_TOO_OFTEN);

        _updateAccountLastPing(account, counter, true);

        ping_balance -= price;

        // Request factory to ping account
        IBoosterFactory(factory).pingAccount{
            value: 0.1 ton,
            flag: 0,
            bounce: false
        }(
            owner,
            counter,
            account,
            settings.farming_pool,
            price,
            _requiredTopUp()
        );
    }

    /// @notice Ping booster account by owner with internal message
    /// Can be called only by `owner`
    /// Can be called anytime after the previous ping is finished (see Constants.PING_DURATION)
    /// @param account Booster account address
    /// @param counter Booster account pings counter, used to prevent double-ping
    function pingByOwner(
        address account,
        uint counter
    ) external override onlyOwner reserveAtLeastTargetBalance accountExists(account) {
        AccountSettings settings = accounts[account];

        require(settings.ping_counter == counter, Errors.BOOSTER_PASSPORT_WRONG_COUNTER);

        _updateAccountLastPing(account, counter, false);

        // Attach gas to the ping
        IBoosterAccount(account).ping{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED,
            bounce: false
        }(counter);
    }

    function getDetails() external override view returns(
        address _owner,
        address _factory,
        uint _version,
        uint[] _managers,
        uint128 _ping_balance,
        uint128 _ping_max_price,
        mapping (address => AccountSettings) _accounts
    ) {
        return (
            owner,
            factory,
            version,
            managers,
            ping_balance,
            ping_max_price,
            accounts
        );
    }

    function _updateAccountLastPing(address account, uint counter, bool byManager) internal {
        uint128 _now = now;

        emit Ping(account, _now, counter, byManager);

        accounts[account].last_ping = _now;
        accounts[account].ping_counter++;
    }

    /// @notice Top up required in case balance is less than target
    function _requiredTopUp() internal pure returns(uint128) {
        if (address(this).balance + Gas.BOOSTER_PASSPORT_SPENT_GAS_LIMIT < _targetBalance()) {
            return _targetBalance() - address(this).balance;
        }

        return 0;
    }

    function _targetBalance() internal pure override returns(uint128) {
        return Gas.BOOSTER_PASSPORT_TARGET_BALANCE;
    }

    function _isArrayIncludes(uint target, uint[] elements) internal pure returns(bool) {
        for (uint element: elements) {
            if (target == element) return true;
        }

        return false;
    }
}
