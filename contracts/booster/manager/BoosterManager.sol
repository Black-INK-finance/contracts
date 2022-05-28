pragma ton-solidity ^0.57.1;
pragma AbiHeader pubkey;

import "../interfaces/IBoosterManager.sol";
import "../interfaces/IBoosterAccount.sol";

import "@broxus/contracts/contracts/access/ExternalOwner.sol";
import "@broxus/contracts/contracts/utils/RandomNonce.sol";


contract BoosterAdmin is IBoosterManager, ExternalOwner, RandomNonce {
    address public internalOwner;
    uint public version;

    constructor(
        uint _owner,
        address _internalOwner
    ) public {
        tvm.accept();

        setOwnership(_owner);
        internalOwner = _internalOwner;
        version = 0;
    }

    function ping(
        Ping[] pings
    ) external override onlyOwner {
        // TODO: add batching
        tvm.accept();

        for (Ping _ping: pings) {
            IBoosterAccount(_ping.account).ping{
                bounce: false,
                flag: 0
            }(_ping.skim);
        }
    }

    function upgrade(
        TvmCell code
    ) external override {
        require(msg.sender == internalOwner);

        TvmCell data = abi.encode(
            _randomNonce,
            owner,
            internalOwner,
            version
        );

        tvm.setcode(code);
        tvm.setCurrentCode(code);

        onCodeUpgrade(data);
    }

    function onCodeUpgrade(TvmCell data) private {
        tvm.resetStorage();

        (
            uint _randomNonce_,
            uint _owner,
            address _internalOwner,
            uint _version
        ) = abi.decode(
            data,
            (
                uint, uint, address, uint
            )
        );

        _randomNonce = _randomNonce_;
        setOwnership(_owner);
        internalOwner = _internalOwner;
        version = _version + 1;
    }

    function getDetails() external override view returns(uint _owner, address _internalOwner, uint _version) {
        return (owner, internalOwner, version);
    }
}
