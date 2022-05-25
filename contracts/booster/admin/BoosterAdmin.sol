pragma ton-solidity ^0.57.1;

import "../interfaces/IBoosterAdmin.sol";
import "../interfaces/IBoosterAccount.sol";

import "@broxus/contracts/contracts/access/ExternalOwner.sol";
import "@broxus/contracts/contracts/utils/RandomNonce.sol";


contract BoosterAdmin is IBoosterAdmin, ExternalOwner, RandomNonce {
    uint128 constant ping_value = 0.5 ton;

    constructor(
        uint _key
    ) public {
        tvm.accept();

        setOwnership(_key);
    }

    function ping(
        address[] accounts
    ) external override onlyOwner {
        tvm.accept();

        for (address account: accounts) {
            IBoosterAccount(account).ping{
                bounce: false,
                value: ping_value
            }();
        }
    }
}
