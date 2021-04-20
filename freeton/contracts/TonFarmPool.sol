pragma ton-solidity ^0.39.0;
pragma AbiHeader expire;

import "./interfaces/IRootTokenContract.sol";
import "./interfaces/ITONTokenWallet.sol";
import "./interfaces/ITokensReceivedCallback.sol";
import "./interfaces/IUserData.sol";
import "./interfaces/ITonFarmPool.sol";
import "./UserData.sol";


contract TonFarmPool is ITokensReceivedCallback, ITonFarmPool {
    // Events
    event Deposit(address user, uint128 amount);
    event Withdraw(address user, uint128 amount);
    event RewardDebt(address user, uint128 amount);

    // ERRORS
    uint8 public constant WRONG_PUBKEY = 100;
    uint8 public constant NOT_OWNER = 101;
    uint8 public constant NOT_ROOT = 102;
    uint8 public constant NOT_TOKEN_WALLET = 103;
    uint8 public constant LOW_DEPOSIT_MSG_VALUE = 104;
    uint8 public constant NOT_USER_DATA = 105;
    uint8 public constant EXTERNAL_CALL = 106;
    uint8 public constant ZERO_AMOUNT_INPUT = 107;
    uint8 public constant LOW_WITHDRAW_MSG_VALUE = 108;
    uint8 public constant FARMING_NOT_ENDED = 109;
    uint8 public constant WRONG_INTERVAL = 110;


    // constants
    uint128 public constant TOKEN_WALLET_DEPLOY_VALUE = 1 ton;
    uint128 public constant GET_WALLET_ADDRESS_VALUE = 0.5 ton;
    uint128 public constant MIN_DEPOSIT_MSG_VALUE = 0.5 ton;
    uint128 public constant MIN_WITHDRAW_MSG_VALUE = 0.5 ton;
    uint128 public constant CONTRACT_MIN_BALANCE = 1 ton;
    uint128 public constant USER_DATA_DEPLOY_VALUE = 0.2 ton;

    // State vars
    uint128 public rewardPerSecond;

    uint128 public lastRewardTime;

    uint128 public accTonPerShare;

    uint128 public farmStartTime;

    uint128 public farmEndTime;

    address public lpTokenRoot;

    address public lpTokenWallet;

    uint128 public lpTokenBalance;

    uint128 public minDeposit;

    address public owner;

    struct PendingDeposit {
        address user;
        uint128 amount;
        address send_gas_to;
    }

    uint64 public nonce = 0;
    // this is used to prevent data loss on bounced messages during deposit
    mapping (uint128 => PendingDeposit) deposits;

    TvmCell public static userDataCode;

    constructor(address _owner, uint128 _rewardPerSecond, uint128 _minDeposit, uint128 _farmStartTime, uint128 _farmEndTime, address _lpTokenRoot) public {
        require (tvm.pubkey() == msg.pubkey(), WRONG_PUBKEY);
        require (_farmStartTime < _farmEndTime, WRONG_INTERVAL);
        tvm.accept();

        rewardPerSecond = _rewardPerSecond;
        minDeposit = _minDeposit;
        farmStartTime = _farmStartTime;
        farmEndTime = _farmEndTime;
        lpTokenRoot = _lpTokenRoot;
        owner = _owner;

        setUpTokenWallet();
    }

    /*
        @notice Creates token wallet for configured root token
    */
    function setUpTokenWallet() internal view {
        // Deploy vault's token wallet
        IRootTokenContract(lpTokenRoot).deployEmptyWallet{value: TOKEN_WALLET_DEPLOY_VALUE}(
            TOKEN_WALLET_DEPLOY_VALUE / 2, // deploy grams
            0, // owner pubkey
            address(this), // owner address
            address(this) // gas refund address
        );

        // Request for token wallet address
        IRootTokenContract(lpTokenRoot).getWalletAddress{
            value: GET_WALLET_ADDRESS_VALUE, callback: TonFarmPool.receiveTokenWalletAddress
        }(0, address(this));
    }

    /*
        @notice Store vault's token wallet address
        @dev Only root can call with correct params
        @param wallet Farm pool's token wallet
    */
    function receiveTokenWalletAddress(
        address wallet
    ) external {
        require(msg.sender == lpTokenRoot, NOT_ROOT);
        lpTokenWallet = wallet;

        ITONTokenWallet(wallet).setReceiveCallback{value: 0.05 ton}(address(this), false);
    }

    // deposit occurs here
    function tokensReceivedCallback(
        address token_wallet,
        address token_root,
        uint128 amount,
        uint256 sender_public_key,
        address sender_address,
        address sender_wallet,
        address original_gas_to,
        uint128 updated_balance,
        TvmCell payload
    ) external override {
        require (msg.sender == lpTokenWallet, NOT_TOKEN_WALLET);
        require (msg.value >= MIN_DEPOSIT_MSG_VALUE, LOW_DEPOSIT_MSG_VALUE);
        tvm.rawReserve(address(this).balance - msg.value, 2);

        if (sender_address.value == 0 || amount < minDeposit) {
            // external owner or too low deposit value
            TvmCell tvmcell;
            ITONTokenWallet(lpTokenWallet).transfer{value: 0, flag: 128}(
                sender_wallet,
                amount,
                0,
                original_gas_to,
                false,
                tvmcell
            );
            return;
        }

        updatePoolInfo();

        nonce += 1;
        deposits[nonce] = PendingDeposit(sender_address, amount, original_gas_to);

        address userDataAddr = getUserDataAddress(sender_address);
        UserData(userDataAddr).processDeposit{value: 0, flag: 128}(nonce, amount, accTonPerShare);
    }

    function finishDeposit(uint64 _nonce, uint128 _prevAmount, uint128 _prevRewardDebt, uint128 _accTonPerShare) external override {
        PendingDeposit deposit = deposits[_nonce];
        address expectedAddr = getUserDataAddress(deposit.user);
        require (expectedAddr == msg.sender, NOT_USER_DATA);

        uint128 pending = 0;
        if (_prevAmount > 0) {
            pending = ((_prevAmount * _accTonPerShare) / 1e18) - _prevRewardDebt;
        }

        if ((pending + msg.value) > address(this).balance) {
            // yeah, not cool, lets hope there will be enough balance
            emit RewardDebt(deposit.user, pending);
            // TODO: write user positive debt and try to return it to user later
            pending = 0;
        }

        tvm.rawReserve(address(this).balance - msg.value - pending, 2);
        lpTokenBalance += deposit.amount;

        if (pending > 0) {
            deposit.user.transfer(pending, false, 1);
        }

        delete deposits[_nonce];
        emit Deposit(deposit.user, deposit.amount);

        deposit.send_gas_to.transfer(0, false, 128);
    }

    function withdraw(uint128 amount, address send_gas_to) public {
        require (msg.sender.value != 0, EXTERNAL_CALL);
        require (amount > 0, ZERO_AMOUNT_INPUT);
        require (msg.value >= MIN_WITHDRAW_MSG_VALUE, LOW_WITHDRAW_MSG_VALUE);
        tvm.rawReserve(address(this).balance - msg.value, 2);

        updatePoolInfo();

        address userDataAddr = getUserDataAddress(msg.sender);
        // we cant check if user has any balance here, delegate it to UserData
        UserData(userDataAddr).processWithdraw{value: 0, flag: 128}(amount, accTonPerShare, send_gas_to);
    }

    function withdrawAll() public {
        require (msg.sender.value != 0, EXTERNAL_CALL);
        require (msg.value >= MIN_WITHDRAW_MSG_VALUE, LOW_WITHDRAW_MSG_VALUE);
        tvm.rawReserve(address(this).balance - msg.value, 2);

        updatePoolInfo();

        address userDataAddr = getUserDataAddress(msg.sender);
        // we cant check if user has any balance here, delegate it to UserData
        UserData(userDataAddr).processWithdrawAll{value: 0, flag: 128}(accTonPerShare, msg.sender);
    }

    function finishWithdraw(address user, uint128 _prevAmount, uint128 _prevRewardDebt, uint128 _withdrawAmount, uint128 _accTonPerShare, address send_gas_to) public override {
        address expectedAddr = getUserDataAddress(user);
        require (expectedAddr == msg.sender, NOT_USER_DATA);

        uint128 pending = ((_prevAmount * _accTonPerShare) / 1e18) - _prevRewardDebt;

        if ((pending + msg.value) > address(this).balance) {
            // yeah, not cool, lets hope there will be enough balance
            emit RewardDebt(user, pending);
            // TODO: write user positive debt and try to return it to user later
            pending = 0;
        }
        tvm.rawReserve(address(this).balance - msg.value - pending, 2);

        lpTokenBalance -= _withdrawAmount;
        if (pending > 0) {
            user.transfer(pending, false, 1);
        }

        TvmCell tvmcell;
        emit Withdraw(user, _withdrawAmount);

        ITONTokenWallet(lpTokenWallet).transferToRecipient{value: 0, flag: 128}(
            0, user, _withdrawAmount, 0, 0, send_gas_to, false, tvmcell
        );
    }

    function finishWithdrawAll(address user, uint128 _prevAmount, uint128 _prevRewardDebt, uint128 _accTonPerShare, address send_gas_to) external override {
        finishWithdraw(user, _prevAmount, _prevRewardDebt, _prevAmount, _accTonPerShare, send_gas_to);
    }

    function withdrawUnclaimed(address to) external view onlyOwner {
        require (now >= farmEndTime, FARMING_NOT_ENDED);
        // minimum value that should remain on contract
        tvm.rawReserve(CONTRACT_MIN_BALANCE, 2);

        to.transfer(0, false, 128);
    }

    // user_amount and user_reward_debt should be fetched from UserData at first
    function pendingReward(uint128 user_amount, uint128 user_reward_debt) external view returns (uint128) {
        uint128 _accTonPerShare = accTonPerShare;
        if (now > lastRewardTime && lpTokenBalance != 0) {
            uint128 multiplier = getMultiplier(lastRewardTime, now);
            uint128 tonReward = multiplier * rewardPerSecond;
            _accTonPerShare += (tonReward * 1e18) / lpTokenBalance;
        }
        return ((user_amount * _accTonPerShare) / 1e18) - user_reward_debt;
    }

    function getMultiplier(uint128 from, uint128 to) public view returns(uint128) {
        require (from <= to, WRONG_INTERVAL);

        if ((from > farmEndTime) || (to < farmStartTime)) {
            return 0;
        }

        if (to > farmEndTime) {
            to = farmEndTime;
        }

        if (from < farmStartTime) {
            from = farmStartTime;
        }

        return to - from;
    }

    // withdraw all staked tokens without reward in case of some critical logic error / insufficient tons on FarmPool balance
    function safeWithdraw(address send_gas_to) external {
        require (msg.sender.value != 0, EXTERNAL_CALL);
        require (msg.value >= MIN_WITHDRAW_MSG_VALUE, LOW_WITHDRAW_MSG_VALUE);
        tvm.rawReserve(address(this).balance - msg.value, 2);

        address user_data_addr = getUserDataAddress(msg.sender);
        IUserData(user_data_addr).processSafeWithdraw{value: 0, flag: 128}(send_gas_to);
    }

    function finishSafeWithdraw(address user, uint128 amount, address send_gas_to) external override {
        address expectedAddr = getUserDataAddress(user);
        require (expectedAddr == msg.sender, NOT_USER_DATA);
        tvm.rawReserve(address(this).balance - msg.value, 2);

        lpTokenBalance -= amount;

        TvmCell tvmcell;
        emit Withdraw(user, amount);

        ITONTokenWallet(lpTokenWallet).transferToRecipient{value: 0, flag: 128}(
            0, user, amount, 0, 0, send_gas_to, false, tvmcell
        );
    }

    function updatePoolInfo() internal {
        if (now <= lastRewardTime) {
            return;
        }

        if (lpTokenBalance == 0) {
            lastRewardTime = now;
            return;
        }

        uint128 multiplier = getMultiplier(lastRewardTime, now);
        uint128 tonReward = rewardPerSecond * multiplier;
        accTonPerShare += tonReward * 1e18 / lpTokenBalance;
        lastRewardTime = now;
    }

    function deployUserData(address _user) internal returns (address) {
        TvmCell stateInit = tvm.buildStateInit({
            contr: UserData,
            varInit: { user: _user, farmPool: address(this) },
            pubkey: tvm.pubkey(),
            code: userDataCode
        });

        return new UserData{
            stateInit: stateInit,
            value: USER_DATA_DEPLOY_VALUE,
            wid: address(this).wid,
            flag: 1
        }();
    }

    function getUserDataAddress(address _user) public view returns (address) {
        TvmCell stateInit = tvm.buildStateInit({
            contr: UserData,
            varInit: { user: _user, farmPool: address(this) },
            pubkey: tvm.pubkey(),
            code: userDataCode
        });
        return address(tvm.hash(stateInit));
    }

    onBounce(TvmSlice slice) external {
        tvm.accept();

        uint32 functionId = slice.decode(uint32);
        // if processing failed - contract was not deployed. Deploy and try again
        if (functionId == tvm.functionId(UserData.processDeposit)) {
            tvm.rawReserve(address(this).balance - msg.value, 2);

            uint64 _nonce = slice.decode(uint64);
            PendingDeposit deposit = deposits[_nonce];
            address user_data_addr = deployUserData(deposit.user);
            // try again
            UserData(user_data_addr).processDeposit{value: 0, flag: 128}(_nonce, deposit.amount, accTonPerShare);
        }
    }

    function upgrade(TvmCell new_code) public onlyOwner {
        TvmBuilder builder;

        // storage vars
        builder.store(rewardPerSecond);
        builder.store(lastRewardTime);
        builder.store(accTonPerShare);
        builder.store(farmStartTime);
        builder.store(farmEndTime);
        builder.store(lpTokenRoot);
        builder.store(lpTokenWallet);
        builder.store(lpTokenBalance);
        builder.store(minDeposit);
        builder.store(owner);
        builder.store(nonce);
        builder.store(deposits);
        builder.store(userDataCode); // ref

        tvm.setcode(new_code);
        tvm.setCurrentCode(new_code);

        onCodeUpgrade(builder.toCell());
    }

    function onCodeUpgrade(TvmCell data) internal {}

    function setRewardPerSecond(uint128 newReward) external onlyOwner {
        tvm.rawReserve(address(this).balance - msg.value, 2);
        updatePoolInfo();
        rewardPerSecond = newReward;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, NOT_OWNER);
        _;
    }
}