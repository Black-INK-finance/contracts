pragma ton-solidity >= 0.39.0;

import "../interfaces/IBoosterBase.sol";


contract BoosterAccountPlatform is IBoosterBase {
    address static owner;
    address static factory;
    address static farming_pool;

    constructor(
        TvmCell code,
        uint version,
        address manager,
        FarmingPoolSettings settings
    ) public {
        require(msg.sender == factory);

        TvmCell data = abi.encode(
            owner,
            factory,
            farming_pool,
            version,
            manager,
            settings
        );

        tvm.setcode(code);
        tvm.setCurrentCode(code);

        onCodeUpgrade(data);
    }

    function onCodeUpgrade(TvmCell data) private {}
}
