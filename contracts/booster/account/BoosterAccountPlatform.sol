pragma ton-solidity >= 0.39.0;

import "../interfaces/IBoosterBase.sol";
//import '@broxus/contracts/contracts/utils/RandomNonce.sol';


contract BoosterAccountPlatform is IBoosterBase {
    address static owner;
    address static factory;
    address static farming_pool;

    constructor(
        TvmCell code,
        uint version,
        address manager,
        uint128 ping_price_limit,
        FarmingPoolSettings settings
    ) public {
        require(msg.sender == factory);

        TvmCell data = abi.encode(
            owner,
            factory,
            farming_pool,

            version,
            manager,
            ping_price_limit,
            settings
        );

        tvm.setcode(code);
        tvm.setCurrentCode(code);

        onCodeUpgrade(data);
    }

    function onCodeUpgrade(TvmCell data) private {}
}
