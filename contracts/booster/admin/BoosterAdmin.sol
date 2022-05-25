pragma ton-solidity ^0.57.1;

import "../interfaces/IBoosterAdmin.sol";
import "@broxus/contracts/contracts/access/InternalOwner.sol";
import "@broxus/contracts/contracts/utils/RandomNonce.sol";


contract BoosterAdmin is IBoosterAdmin, InternalOwner, RandomNonce {
    constructor(
        address _owner
    ) public {
        setOwnership(_owner);
    }
}
