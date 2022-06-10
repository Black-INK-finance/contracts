pragma ton-solidity ^0.57.1;
pragma AbiHeader time;
pragma AbiHeader pubkey;
pragma AbiHeader expire;


import "./../TransferUtils.sol";
import "./../Constants.sol";
import "./../Errors.sol";

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
    mapping (address => AccountSettings) accounts;

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
            address remainingGasTo
        ) = abi.decode(data, (address, address, uint, address));

        tvm.rawReserve(_targetBalance(), 2);

        factory = _factory;
        setOwnership(_owner);
        version = _version;

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

//    function afterSignatureCheck(TvmSlice body, TvmCell message) private inline view returns (TvmSlice) {
//        body.decode(uint64, uint32);
//        TvmSlice bodyCopy = body;
//        uint32 functionId = body.decode(uint32);
//
//        (,address account,) = abi.decode(message, (uint128, address, uint));
//
//        require(account.exists(account), Utils.PASSPORT_ACCOUNT_NOT_EXISTS);
//
//        AccountSettings settings = accounts[account];
//
//        if (functionId == tvm.functionId(ping)) {
//            require(settings.last_ping + settings.frequency <= now, Errors.PASSPORT_PING_TOO_OFTEN);
//        }
//
//        return bodyCopy;
//    }

    /// @notice Accept ping token top up
    /// Can be called only by `factory`
    /// @param amount Amount of ping tokens to accept
    function acceptPingTokens(
        uint128 amount,
        address remainingGasTo
    ) external override onlyFactory cashBack(remainingGasTo) {
        ping_balance += amount;
    }

    /// @notice Set ping frequency
    /// Can be called only by `owner`
    /// @param account Booster account address
    /// @param frequency New ping frequency
    function setPingFrequency(
        address account,
        uint128 frequency
    ) external override onlyOwner accountExists(account) cashBack(msg.sender) {
        require(frequency >= Constants.MIN_PING_FREQUENCY);

        accounts[account].ping_frequency = frequency;
    }

    function setManagers(
        uint[] _managers,
        address remainingGasTo
    ) external override onlyFactory cashBack(remainingGasTo) {
        managers = _managers;
    }

    function registerAccount(
        address account,
        uint128 ping_frequency,
        address remainingGasTo
    ) external override onlyFactory cashBack(remainingGasTo) {
        accounts[account] = AccountSettings({
            ping_frequency: ping_frequency,
            last_ping: 0,
            ping_counter: 0,
            auto_ping_enabled: true
        });
    }

    /// @notice Toggle account auto ping
    /// Can be called only by `owner`
    /// @param account Booster account address
    function toggleAccountAutoPing(
        address account
    ) external override onlyOwner accountExists(account) cashBack(msg.sender) {
        accounts[account].auto_ping_enabled = !accounts[account].auto_ping_enabled;
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
    ) external override onlyManager {
        // - Manager uses external in message, passport pays itself

        // TODO: infinite error? use tvm commit? or timestamp
        tvm.accept();

        _updateAccountLastPing(account);

        AccountSettings settings = accounts[account];

        require(ping_balance >= price, Errors.BOOSTER_PASSPORT_PING_BALANCE_TOO_LOW);
        require(settings.ping_counter == counter, Errors.BOOSTER_PASSPORT_WRONG_COUNTER);
        require(ping_max_price >= price, Errors.BOOSTER_PASSPORT_PRICE_TOO_HIGH);
        require(settings.auto_ping_enabled, Errors.BOOSTER_PASSPORT_AUTO_PING_DISABLED);

        ping_balance -= price;

        // Request factory to ping account
        IBoosterFactory(factory).pingAccount{
            value: 0,
            flag: 0,
            bounce: false
        }(
            owner,
            counter + 1,
            account,
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

        require(settings.last_ping + Constants.PING_DURATION >= now, Errors.BOOSTER_PASSPORT_PING_NOT_FINISHED);
        require(settings.ping_counter == counter, Errors.BOOSTER_PASSPORT_WRONG_COUNTER);

        _updateAccountLastPing(account);

        // Attach gas to the ping
        IBoosterAccount(account).ping{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED,
            bounce: false
        }(counter + 1, owner);
    }

    function _updateAccountLastPing(address account) internal {
        accounts[account].last_ping = now;
        accounts[account].ping_counter++;
    }

    /// @notice Top up required in case balance is less than half of the `_targetBalance`
    function _requiredTopUp() internal pure returns(uint128) {
        uint128 threshold = _targetBalance() / 2;
        uint128 balance = address(this).balance;

        return (address(this).balance < threshold) ? (balance - threshold) : 0;
    }

    function _targetBalance() internal pure override returns(uint128) {
        return 1 ton;
    }

    function _isArrayIncludes(uint target, uint[] elements) internal pure returns(bool) {
        for (uint element: elements) {
            if (target == element) return true;
        }

    return false;
    }
}
