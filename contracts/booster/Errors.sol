pragma ton-solidity ^0.57.1;


library Errors {
    // Common
    uint16 constant WRONG_SENDER = 2000;

    // Passport
    uint16 constant BOOSTER_PASSPORT_PING_BALANCE_TOO_LOW = 2100;
    uint16 constant BOOSTER_PASSPORT_WRONG_COUNTER = 2101;
    uint16 constant BOOSTER_PASSPORT_PRICE_TOO_HIGH = 2102;
    uint16 constant BOOSTER_PASSPORT_AUTO_PING_DISABLED = 2103;
    uint16 constant BOOSTER_PASSPORT_PING_TOO_OFTEN = 2104;
    uint16 constant BOOSTER_PASSPORT_ACCOUNT_NOT_EXISTS = 2105;
    uint16 constant BOOSTER_PASSPORT_ACCOUNT_ALREADY_REGISTERED = 2106;
    uint16 constant BOOSTER_PASSPORT_PING_FREQUENCY_TOO_LOW = 2107;

    // Account
    // Buyback
    // Factory
    uint16 constant BOOSTER_FACTORY_WRONG_ACCOUNT = 2200;
    uint16 constant BOOSTER_FACTORY_FARMING_NOT_EXISTS = 2201;
}
