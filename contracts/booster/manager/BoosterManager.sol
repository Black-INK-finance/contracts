pragma ton-solidity ^0.57.1;
pragma AbiHeader pubkey;

import "../interfaces/IBoosterManager.sol";
import "../interfaces/IBoosterAccount.sol";

import "@broxus/contracts/contracts/access/ExternalOwner.sol";
import "@broxus/contracts/contracts/utils/RandomNonce.sol";


contract BoosterAdmin is IBoosterManager, ExternalOwner, RandomNonce {
    uint128 constant ping_value = 2 ton;

    address public internalOwner;

    constructor(
        uint _owner,
        address _internalOwner
    ) public {
        tvm.accept();

        setOwnership(_owner);
        internalOwner = _internalOwner;
    }

    function ping(
        Ping[] pings
    ) external override onlyOwner {
        // TODO: add batching
        tvm.accept();

        for (Ping _ping: pings) {
            IBoosterAccount(_ping.account).ping{
                bounce: false,
                value: ping_value
            }(_ping.skim);
        }
    }
}
