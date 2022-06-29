pragma ton-solidity ^0.57.1;

import "./IBoosterBase.sol";
import {IDexPair} from "flatqube/contracts/interfaces/IDexPair.sol";


interface IBoosterAccount is IBoosterBase {
    struct Token {
        uint128 balance;
        uint128 received;
        address wallet;
        uint128 fee;
    }

    struct PairBalance {
        uint128 left;
        uint128 right;
    }

    struct PairBalancesLoader {
        uint32 total;
        uint32 loaded;
    }

    function getDetails() external view returns (
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
    );

    // Manager methods
    function ping(
        uint64 counter
    ) external;

    function skim(address remainingGasTo) external;
    function skimGas() external;

    // Factory methods
    function setFees(
        uint128 _lp_fee,
        uint128 _reward_fee,
        address remainingGasTo
    ) external;

    function setSwaps(
        mapping (address => SwapDirection) _swaps,
        address remainingGasTo
    ) external;

    function setRewarder(
        address _rewarder,
        address remainingGasTo
    ) external;
    function toggleAutoReinvestment() external;

    function updateSlippage(
        uint128 _slippage
    ) external;

    function updateSettings(TvmCell settings) external;

    function acceptUpgrade(
        TvmCell code,
        uint version
    ) external;

    function isInitialized() external view returns(bool);

    // Owner methods
    function requestFarmingLP(
        uint128 amount,
        bool toggle_auto_reinvestment
    ) external;

    // Technical methods
    function receiveTokenWallet(address wallet) external;
    function receiveFarmingUserData(address _user_data) external;
    function receiveDexPairBalances(IDexPair.IDexPairBalances balances) external;

    event AccountReceivedTokensTransfer(address root, uint128 amount, address sender);
    event AccountReceivedTokensMint(address root, uint128 amount);

    event AccountTokensSentToOwner(address root, address sender, uint128 amount);
    event AccountGainedReward(address reward, uint128 gain, uint128 fee);
    event AccountGainedLp(uint128 gain, uint128 fee);
    event AccountSwap(address _from, address _to, uint128 expectedAmount, bool gained);
    event AutoReinvestmentUpdated(bool auto_reinvestment);
    event SlippageUpdated(uint128 slippage);
}
