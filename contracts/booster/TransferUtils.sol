pragma ton-solidity ^0.57.1;


abstract contract TransferUtils {
    modifier cashBack() {
        tvm.rawReserve(address(this).balance - msg.value, 2);
        _;
        msg.sender.transfer({ value: 0, flag: 129 });
    }

    modifier reserveBalance() {
        tvm.rawReserve(address(this).balance - msg.value, 2);
        _;
    }
}
