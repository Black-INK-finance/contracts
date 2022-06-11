pragma ton-solidity ^0.57.1;


contract BoosterPassportPlatform {
    address static factory;
    address static owner;

    constructor(
        TvmCell code,
        uint version,
        uint[] managers,
        uint128 max_ping_price,
        address remainingGasTo
    ) public {
        require(msg.sender == factory);

        tvm.setcode(code);
        tvm.setCurrentCode(code);

        TvmCell data = abi.encode(
            factory,
            owner,
            version,
            managers,
            max_ping_price,
            remainingGasTo
        );

        onCodeUpgrade(data);
    }

    function onCodeUpgrade(TvmCell) private {}
}
