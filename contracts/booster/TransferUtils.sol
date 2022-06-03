pragma ton-solidity ^0.57.1;


abstract contract TransferUtils {
    modifier cashBack(address receiver) {
        tvm.rawReserve(address(this).balance - msg.value, 2);
        _;

        receiver.transfer({ value: 0, flag: 129 });
    }

    modifier reserveBalance() {
        tvm.rawReserve(address(this).balance - msg.value, 2);
        _;
    }

    function _targetBalance() internal pure virtual returns(uint128) {
        return 10 ton;
    }
}
