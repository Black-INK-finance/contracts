const logger = require("mocha-logger");
const chai = require('chai');
chai.use(require('chai-bignumber')());

const { expect } = chai;
const {
    convertCrystal
} = locklift.utils;

const _ = require('underscore');


// ------------------------------- UTILS -----------------------------------
async function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

const TOKEN_CONTRACTS_PATH = './node_modules/broxus-ton-tokens-contracts/build';
const DEX_CONTRACTS_PATH = './node_modules/flatqube/build';

const isValidTonAddress = (address) => /^(?:-1|0):[0-9a-fA-F]{64}$/.test(address);

const getRandomNonce = locklift.utils.getRandomNonce;

const afterRun = async (tx) => {
    if (locklift.network === 'dev' || locklift.network === 'main') {
        await sleep(100000);
    }
    await sleep(1000);
};


const wait_acc_deployed = async function (addr) {
    await locklift.ton.client.net.wait_for_collection({
        collection: 'accounts',
        filter: {
            id: { eq: addr },
            balance: { gt: `0x0` }
        },
        result: 'id'
    });
}


const calcExpectedReward = function(prevRewardTime, newRewardTime, _rewardPerSec) {
    const time_passed = newRewardTime - prevRewardTime;
    return _rewardPerSec * time_passed;
}

const checkReward = async function(userWallet, prevBalance, prevRewardTime, newRewardTime, _rewardPerSec) {
    const user_bal_after = await userWallet.balance();
    // console.log(user_bal_after.toString());
    // console.log(prevBalance.toString());
    const reward = user_bal_after - prevBalance;
    // console.log(user_bal_after, prevBalance)

    const expected_reward = calcExpectedReward(prevRewardTime, newRewardTime, _rewardPerSec);

    expect(reward).to.be.equal(expected_reward, 'Bad reward');
    return expected_reward;
}


// -------------------------- ENTITIES ----------------------------
class TokenWallet {
    constructor(wallet_contract, wallet_owner) {
        this.wallet = wallet_contract;
        this._owner = wallet_owner;
        this.address = this.wallet.address;
    }

    static async from_addr(addr, owner) {
        let userTokenWallet = await locklift.factory.getContract(
            'TokenWallet',
            'node_modules/broxus-ton-tokens-contracts/build'
        );

        userTokenWallet.setAddress(addr);
        return new TokenWallet(userTokenWallet, owner);
    }

    async owner() {
        return await this.wallet.call({method: 'owner'});
    }

    async root() {
        return await this.wallet.call({method: 'root'});
    }

    async balance() {
        return await this.wallet.call({method: 'balance'});
    }

    async transfer(amount, receiver_or_addr, payload='', tracing=null, allowed_codes={compute: []}) {
        let addr = receiver_or_addr.address;
        if (addr === undefined) {
            addr = receiver_or_addr;
        }
        let notify = false;
        if (payload) {
            notify = true;
        }
        return await this._owner.runTarget({
            contract: this.wallet,
            method: 'transfer',
            params: {
                amount: amount,
                recipient: addr,
                deployWalletValue: 0,
                remainingGasTo: this._owner.address,
                notify: true,
                payload: payload
            },
            value: convertCrystal(10, 'nano'),
            tracing: tracing,
            tracing_allowed_codes: allowed_codes
        });
    }
}


class Token {
    constructor(token_contract, token_owner) {
        this.token = token_contract;
        this.owner = token_owner;
        this.address = this.token.address;
    }

    static async from_addr (addr, owner) {
        const rootToken = await locklift.factory.getContract(
            'TokenRoot',
            'node_modules/broxus-ton-tokens-contracts/build'
        );
        rootToken.setAddress(addr);
        return new Token(rootToken, owner);
    }

    async walletAddr(user_or_addr) {
        let addr = user_or_addr.address;
        if (addr === undefined) {
            addr = user_or_addr;
        }
        return await this.token.call({
            method: 'walletOf',
            params: { walletOwner: addr }
        });
    }

    async wallet(user) {
        const wallet_addr = await this.walletAddr(user);
        return TokenWallet.from_addr(wallet_addr, user);
    }

    async name() {
        return this.token.call({ method: 'name' });
    }

    async symbol() {
        return this.token.call({ method: 'symbol' });
    }

    async deployWallet(user) {
        await user.runTarget({
            contract: this.token,
            method: 'deployWallet',
            params: {
                answerId: 0,
                walletOwner: user.address,
                deployWalletValue: convertCrystal(1, 'nano'),
            },
            value: convertCrystal(2, 'nano'),
        });
        const addr = await this.walletAddr(user);
        await wait_acc_deployed(addr);

        logger.log(`User token wallet: ${addr}`);
        return TokenWallet.from_addr(addr, user);
    }

    async mint(mint_amount, user) {
        await this.owner.runTarget({
            contract: this.token,
            method: 'mint',
            params: {
                amount: mint_amount,
                recipient: user.address,
                deployWalletValue: convertCrystal(1, 'nano'),
                remainingGasTo: this.owner.address,
                notify: false,
                payload: ''
            },
            value: convertCrystal(3, 'nano'),
        });

        const walletAddr = await this.walletAddr(user);

        await wait_acc_deployed(walletAddr);

        // logger.log(`User token wallet: ${walletAddr}`);
        return TokenWallet.from_addr(walletAddr, user);
    }
}


class FarmPool {
    constructor(pool_contract, pool_owner) {
        this.pool = pool_contract;
        this.owner = pool_owner;
        this.address = this.pool.address;
    }

    async details() {
        return await this.pool.call({method: 'getDetails'});
    }

    async lastRewardTime() {
        const details = await this.details();
        return details.lastRewardTime;
    }

    async version() {
        const details = await this.details();
        return details.pool_version;
    }

    async user_data_version() {
        const details = await this.details();
        return details.user_data_version;
    }

    async tokenBalance() {
        const res = await this.details();
        return res.tokenBalance;
    }

    async userData(user, name='UserDataV2') {
        const addr = await this.pool.call({method: 'getUserDataAddress', params: {user: user.address}});
        const userData = await locklift.factory.getContract(name);
        userData.setAddress(addr);
        return userData;
    }

    async wallet() {
        if (this._wallet !== undefined) {
            return this._wallet;
        }
        const details = await this.details();
        this._wallet = TokenWallet.from_addr(details.tokenWallet);
        return this._wallet;
    }

    async rewardWallets() {
        if (this._rewardWallets !== undefined) {
            return this._rewardWallets;
        }
        const details = await this.details();
        this._rewardWallets = await Promise.all(details.rewardTokenWallet.map(async (wallet_addr) => {
            return TokenWallet.from_addr(wallet_addr);
        }));
        return this._rewardWallets;
    }

    async depositPayload(deposit_owner_or_addr) {
        let addr = deposit_owner_or_addr.address;
        if (addr === undefined) {
            addr = deposit_owner_or_addr;
        }
        return await this.pool.call({
            method: 'encodeDepositPayload',
            params: {
                deposit_owner: addr,
                nonce: 0
            }
        });
    }

    async deposit(from_wallet, amount, deposit_owner, tracing_errors={compute: [null]}) {
        if (deposit_owner === undefined) {
            deposit_owner = from_wallet._owner;
        }
        const payload = await this.depositPayload(deposit_owner);
        return await from_wallet.transfer(amount, this.pool, payload, null, tracing_errors);
    }

    async claimRewardForUser(caller, user, tracing_errors={compute: []}) {
        return await caller.runTarget({
            contract: this.pool,
            method: 'claimRewardForUser',
            params: {
                user: user.address,
                send_gas_to: user.address,
                nonce: 0
            },
            value: convertCrystal(5, 'nano'),
            tracing_allowed_codes: tracing_errors
        });
    }

    async withdrawUnclaimed() {
        return await this.owner.runTarget({
            contract: this.pool,
            method: 'withdrawUnclaimed',
            params: {
                to: this.owner.address,
                send_gas_to: this.owner.address,
                nonce: 0
            },
            value: convertCrystal(5, 'nano')
        })
    }

    async withdrawTokens(user, withdraw_amount, tracing_errors={compute: []}) {
        return await user.runTarget({
            contract: this.pool,
            method: 'withdraw',
            params: {
                amount: withdraw_amount,
                send_gas_to: user.address,
                nonce: 0
            },
            value: convertCrystal(5, 'nano'),
            tracing_allowed_codes: tracing_errors
        });
    };

    async safeWithdraw(user) {
        return await user.runTarget({
            contract: this.pool,
            method: 'safeWithdraw',
            params: {
                send_gas_to: user.address
            },
            value: convertCrystal(5, 'nano')
        });
    }

    async withdrawUnclaimedAll() {
        return await this.owner.runTarget({
            contract: this.pool,
            method: 'withdrawUnclaimedAll',
            params: {
                to: this.owner.address,
                send_gas_to: this.owner.address,
                nonce: 0
            },
            value: convertCrystal(5, 'nano')
        })
    }

    async claimReward(user, tracing_errors={compute: []}) {
        return await user.runTarget({
            contract: this.pool,
            method: 'claimReward',
            params: {
                send_gas_to: user.address,
                nonce: 0
            },
            value: convertCrystal(5, 'nano'),
            tracing_allowed_codes: tracing_errors
        });
    };

    async withdrawAllTokens(user) {
        return await user.runTarget({
            contract: this.pool,
            method: 'withdrawAll',
            params: {send_gas_to: user.address, nonce: 0},
            value: convertCrystal(5, 'nano')
        });
    }

    async addRewardRound(start_time, reward_per_sec) {
        return await this.owner.runTarget({
            contract: this.pool,
            method: 'addRewardRound',
            params: {reward_round: {startTime: start_time, rewardPerSecond: reward_per_sec}, send_gas_to: this.owner.address},
            value: convertCrystal(1.5, 'nano')
        });
    }

    async requestUpdateUserDataCode() {
        return await this.owner.runTarget({
            contract: this.pool,
            method: 'requestUpdateUserDataCode',
            params: {send_gas_to: this.owner.address},
            value: convertCrystal(2, 'nano')
        });
    }

    async requestUpgradePool() {
        return await this.owner.runTarget({
            contract: this.pool,
            method: 'requestUpgradePool',
            params: {send_gas_to: this.owner.address},
            value: convertCrystal(2, 'nano')
        });
    }

    async setFarmEndTime(farm_end_time) {
        return await this.owner.runTarget({
            contract: this.pool,
            method: 'setEndTime',
            params: {farm_end_time: farm_end_time, send_gas_to: this.owner.address},
            value: convertCrystal(1.5, 'nano')
        });
    }

    async getEvents(event_name) {
        return await this.pool.getEvents(event_name);
    }

    async upgradeUserData(user) {
        return await user.runTarget({
            contract: this.pool,
            method: 'upgradeUserData',
            params: {send_gas_to: user.address},
            value: convertCrystal(1.5, 'nano')
        });
    }

    static async from_addr(addr, owner, name='EverFarmPool') {
        const pool = await locklift.factory.getContract(name);
        pool.setAddress(addr);
        return new FarmPool(pool, owner);
    }
}


class Fabric {
    constructor(fabric_contract, fabric_owner) {
        this.fabric = fabric_contract;
        this.owner = fabric_owner;
        this.address = fabric_contract.address;
    }

    async deployPool({pool_owner, reward_rounds, tokenRoot, rewardTokenRoot, vestingPeriod, vestingRatio, withdrawAllLockPeriod}) {
        const deploy_tx = await this.owner.runTarget({
            contract: this.fabric,
            method: 'deployFarmPool',
            params: {
                pool_owner: pool_owner.address,
                reward_rounds: reward_rounds,
                tokenRoot: tokenRoot,
                rewardTokenRoot: rewardTokenRoot,
                vestingPeriod: vestingPeriod,
                vestingRatio: vestingRatio,
                withdrawAllLockPeriod: withdrawAllLockPeriod
            },
            value: convertCrystal(10, 'nano')
        });

        const {
            value: {
                pool: _pool,
                pool_owner: _owner,
                reward_rounds: _rewardRounds,
                tokenRoot: _tokenRoot,
                rewardTokenRoot: _rewardTokenRoot
            }
        } = (await this.fabric.getEvents('NewFarmPool')).pop();

        expect(_owner).to.be.equal(pool_owner.address, "Wrong owner");

        logger.log(`Farm Pool address: ${_pool}`);
        // Wait until farm farm pool is indexed
        await wait_acc_deployed(_pool);
        const _farm_pool = await locklift.factory.getContract('EverFarmPool');
        _farm_pool.setAddress(_pool);

        const pool = new FarmPool(_farm_pool, pool_owner);
        await this._checkPoolDeployedCorrectly(pool, tokenRoot, rewardTokenRoot);

        return pool;
    }

    async _checkPoolDeployedCorrectly(pool, tokenRoot, rewardTokenRoot) {
        const token = await Token.from_addr(tokenRoot);
        const expectedWalletAddr = await token.walletAddr(pool);
        await wait_acc_deployed(expectedWalletAddr);

        await Promise.all(rewardTokenRoot.map(async (wallet_addr, idx) => {
            const token = await Token.from_addr(wallet_addr);
            const expectedWalletAddr = await token.walletAddr(pool, rewardTokenRoot[idx]);
            await wait_acc_deployed(expectedWalletAddr);

        }));

        const pool_details = await pool.details();
        logger.log(`Farm Pool token wallet: ${pool_details.tokenWallet}`);

        const farm_pool_wallet = await pool.wallet();
        const farm_pool_reward_wallets = await pool.rewardWallets();

        const addrs = farm_pool_reward_wallets.map((wallet) => { return wallet.address });
        logger.log(`Farm Pool reward token wallets: ${addrs}`);

        const owner = await farm_pool_wallet.owner();
        const root_ = await farm_pool_wallet.root();

        expect(owner).to.be.equal(pool.address, 'Wrong farm pool token wallet owner');
        expect(root_).to.be.equal(tokenRoot, 'Wrong farm pool token wallet owner');

        await Promise.all(farm_pool_reward_wallets.map(async (wallet, idx) => {
            const owner1 = await wallet.owner();
            const root1_ = await wallet.root();

            expect(owner1).to.be.equal(pool.address, 'Wrong farm pool token wallet owner');
            expect(root1_).to.be.equal(rewardTokenRoot[idx], 'Wrong farm pool token wallet owner');
        }));

    }

    async installNewFarmPoolCode(code) {
        return await this.owner.runTarget({
            contract: this.fabric,
            method: 'installNewFarmPoolCode',
            params: {farm_pool_code: code, send_gas_to: this.owner.address},
            value: convertCrystal(1.5, 'nano')
        });
    }

    async installNewUserDataCode(code) {
        return await this.owner.runTarget({
            contract: this.fabric,
            method: 'installNewUserDataCode',
            params: {user_data_code: code, send_gas_to: this.owner.address},
            value: convertCrystal(1.5, 'nano')
        });
    }

    async upgradePools(pool) {
        return await this.owner.runTarget({
            contract: this.fabric,
            method: 'upgradePools',
            params: {pools: [pool.address], send_gas_to: this.owner.address},
            value: convertCrystal(2.5, 'nano')
        });
    }

    async updatePoolsUserDataCode(pool) {
        return await this.owner.runTarget({
            contract: this.fabric,
            method: 'updatePoolsUserDataCode',
            params: {pools: [pool.address], send_gas_to: this.owner.address},
            value: convertCrystal(2.5, 'nano')
        });
    }

    async forceUpdateUserData(pool, user) {
        return await this.owner.runTarget({
            contract: this.fabric,
            method: 'forceUpdateUserData',
            params: {pool: pool.address, user: user.address, send_gas_to: this.owner.address},
            value: convertCrystal(2.5, 'nano')
        });
    }
    async pool_version() {
        return await this.fabric.call({method: 'farm_pool_version'});
    }

    async user_data_version() {
        return await this.fabric.call({method: 'user_data_version'});
    }

    async fabric_version() {
        return await this.fabric.call({method: 'fabric_version'});
    }

    async upgrade(new_code) {
        return await this.owner.runTarget({
            contract: this.fabric,
            method: 'upgrade',
            params: {new_code: new_code, send_gas_to: this.owner.address},
            value: convertCrystal(2.5, 'nano')
        });
    }

    async getEvents(event_name) {
        return await this.fabric.getEvents(event_name);
    }

    static async from_addr(addr, owner, name='FarmFabric') {
        const fabric = await locklift.factory.getContract(name);
        fabric.setAddress(addr);
        return new Fabric(fabric, owner);
    }
}


// -------------------------- SETUP METHODS --------------------------
const setupFabric = async (owner, fabric_version=2, pool_version=2, user_data_version=2) => {
    const fabric_codes = {
        0: await locklift.factory.getContract('FarmFabric'),
        1: await locklift.factory.getContract('FarmFabricV2'),
        2: await locklift.factory.getContract('FarmFabricV3')

    };
    const pool_codes = {
        0: await locklift.factory.getContract('EverFarmPool'),
        1: await locklift.factory.getContract('EverFarmPoolV2'),
        2: await locklift.factory.getContract('EverFarmPoolV3')
    };
    const user_data_codes = {
        0: await locklift.factory.getContract('UserData'),
        1: await locklift.factory.getContract('UserDataV2'),
        2: await locklift.factory.getContract('UserDataV3')
    }

    const PoolFabric = fabric_codes[fabric_version];
    const EverFarmPool = pool_codes[pool_version];
    const UserData = user_data_codes[user_data_version];

    const Platform = await locklift.factory.getContract('Platform');

    const [keyPair] = await locklift.keys.getKeyPairs();
    const fabric = await locklift.giver.deployContract({
        contract: PoolFabric,
        constructorParams: {
            _owner: owner.address
        },
        initParams: {
            FarmPoolCode: EverFarmPool.code,
            FarmPoolUserDataCode: UserData.code,
            PlatformCode: Platform.code,
            nonce: locklift.utils.getRandomNonce()
        },
        keyPair,
    }, convertCrystal(1, 'nano'));

    logger.log(`Pool Fabric address: ${fabric.address}`);

    const {
        acc_type_name
    } = await locklift.ton.getAccountType(fabric.address);

    expect(acc_type_name).to.be.equal('Active', 'Fabric account not active');

    return new Fabric(fabric, owner);
}


const setupTokenRoot = async function(token_name, token_symbol, owner) {
    const RootToken = await locklift.factory.getContract(
        'TokenRootUpgradeable',
        'node_modules/broxus-ton-tokens-contracts/build'
    );

    const TokenWalletPlatform = await locklift.factory.getContract(
        'TokenWalletPlatform',
        'node_modules/broxus-ton-tokens-contracts/build'
    );

    const TokenWallet = await locklift.factory.getContract(
        'TokenWalletUpgradeable',
        'node_modules/broxus-ton-tokens-contracts/build'
    );

    const [keyPair] = await locklift.keys.getKeyPairs();

    const _root = await locklift.giver.deployContract({
        contract: RootToken,
        constructorParams: {
            initialSupplyTo: locklift.utils.zeroAddress,
            initialSupply: 0,
            deployWalletValue: locklift.utils.convertCrystal(0.2, 'nano'),
            mintDisabled: false,
            burnByRootDisabled: false,
            burnPaused: false,
            remainingGasTo: owner.address
        },
        initParams: {
            randomNonce_: locklift.utils.getRandomNonce(),
            deployer_: locklift.utils.zeroAddress,
            name_: token_name,
            symbol_: token_symbol,
            decimals_: 9,
            rootOwner_: owner.address,
            walletCode_: TokenWallet.code,
            platformCode_: TokenWalletPlatform.code
        },
        keyPair,
    });
    _root.afterRun = afterRun;
    _root.setKeyPair(keyPair);

    const name = await _root.call({
        method: 'name',
        params: {}
    });

    expect(name.toString()).to.be.equal(token_name, 'Wrong root name');
    expect((await locklift.ton.getBalance(_root.address)).toNumber()).to.be.above(0, 'Root balance empty');

    _root.name = `Token root [${token_symbol}]`;

    await logContract(_root);

    return new Token(_root, owner);
}


const getUserDataDetails = async function(userData) {
    return await userData.call({method: 'getDetails'});
}


const deployUser = async function(name = '', amount = 200) {
    const [keyPair] = await locklift.keys.getKeyPairs();
    const Account = await locklift.factory.getAccount('Wallet');
    const _user = await locklift.giver.deployContract({
        contract: Account,
        constructorParams: {},
        initParams: {
            _randomNonce: locklift.utils.getRandomNonce()
        },
        keyPair,
    }, convertCrystal(amount, 'nano'));

    _user.afterRun = afterRun;

    _user.setKeyPair(keyPair);

    if (name !== '') {
        _user.name = name;
    }

    const userBalance = await locklift.ton.getBalance(_user.address);

    expect(userBalance.toNumber()).to.be.above(0, 'Bad user balance');

    await logContract(_user);

    const {
        acc_type_name
    } = await locklift.ton.getAccountType(_user.address);

    expect(acc_type_name).to.be.equal('Active', 'User account not active');
    return _user;
}

const logContract = async (contract) => {
    const balance = await locklift.ton.getBalance(contract.address);

    logger.log(`${contract.name} (${contract.address}) - ${locklift.utils.convertCrystal(balance, 'ton')}`);
};


const setupDex = async (god) => {
    const [keyPair] = await locklift.keys.getKeyPairs();

    // Deploy token factory
    const TokenFactory = await locklift.factory.getContract('TokenFactory', DEX_CONTRACTS_PATH);

    const TokenRoot = await locklift.factory.getContract('TokenRootUpgradeable', TOKEN_CONTRACTS_PATH);
    const TokenWallet = await locklift.factory.getContract('TokenWalletUpgradeable', TOKEN_CONTRACTS_PATH);
    const TokenWalletPlatform = await locklift.factory.getContract('TokenWalletPlatform', TOKEN_CONTRACTS_PATH);

    const token_factory = await locklift.giver.deployContract({
        contract: TokenFactory,
        constructorParams: {
            _owner: god.address
        },
        initParams: {
            randomNonce_: getRandomNonce(),
        },
        keyPair,
    }, locklift.utils.convertCrystal(2, 'nano'));

    await god.runTarget({
        contract: token_factory,
        method: 'setRootCode',
        params: {_rootCode: TokenRoot.code},
        keyPair
    });

    await god.runTarget({
        contract: token_factory,
        method: 'setWalletCode',
        params: {_walletCode: TokenWallet.code},
    });

    await god.runTarget({
        contract: token_factory,
        method: 'setWalletPlatformCode',
        params: {_walletPlatformCode: TokenWalletPlatform.code},
    });

    await logContract(token_factory);

    // Deploy dex root
    const DexPlatform = await locklift.factory.getContract(
        'DexPlatform',
        DEX_CONTRACTS_PATH
    );
    const DexAccount = await locklift.factory.getContract(
        'DexAccount',
        DEX_CONTRACTS_PATH
    );
    const DexPair = await locklift.factory.getContract(
        'DexPair',
        DEX_CONTRACTS_PATH
    );
    const DexVaultLpTokenPending = await locklift.factory.getContract(
        'DexVaultLpTokenPending',
        DEX_CONTRACTS_PATH
    );
    const DexRoot = await locklift.factory.getContract(
        'DexRoot',
        DEX_CONTRACTS_PATH
    );
    const DexVault = await locklift.factory.getContract(
        'DexVault',
        DEX_CONTRACTS_PATH
    );

    const dex_root = await locklift.giver.deployContract({
        contract: DexRoot,
        constructorParams: {
            initial_owner: god.address,
            initial_vault: locklift.ton.zero_address
        },
        initParams: {
            _nonce: locklift.utils.getRandomNonce(),
        },
        keyPair,
    }, locklift.utils.convertCrystal(2, 'nano'));

    await logContract(dex_root);

    const dex_vault = await locklift.giver.deployContract({
        contract: DexVault,
        constructorParams: {
            owner_: god.address,
            token_factory_: token_factory.address,
            root_: dex_root.address
        },
        initParams: {
            _nonce: getRandomNonce(),
        },
        keyPair,
    }, locklift.utils.convertCrystal(2, 'nano'));

    await logContract(dex_vault);

    await god.runTarget({
        contract: dex_vault,
        method: 'installPlatformOnce',
        params: {code: DexPlatform.code},
    });

    await god.runTarget({
        contract: dex_vault,
        method: 'installOrUpdateLpTokenPendingCode',
        params: {code: DexVaultLpTokenPending.code},
    });

    await god.runTarget({
        contract: dex_root,
        method: 'setVaultOnce',
        params: {new_vault: dex_vault.address},
    });

    await god.runTarget({
        contract: dex_root,
        method: 'installPlatformOnce',
        params: {code: DexPlatform.code},
    });

    await god.runTarget({
        contract: dex_root,
        method: 'installOrUpdateAccountCode',
        params: {code: DexAccount.code},
    });

    await god.runTarget({
        contract: dex_root,
        method: 'installOrUpdatePairCode',
        params: {code: DexPair.code, pool_type: 1},
    });

    await god.runTarget({
        contract: dex_root,
        method: 'installOrUpdatePairCode',
        params: {code: DexPair.code, pool_type: 2},
    });

    await god.runTarget({
        contract: dex_root,
        method: 'setActive',
        params: {new_active: true},
    });

    return [token_factory, dex_root, dex_vault];
};

const deployDexPair = async (owner, dex_root, left, right) => {
    await owner.runTarget({
        contract: dex_root,
        method: 'deployPair',
        params: {
            left_root: left.address,
            right_root: right.address,
            send_gas_to: owner.address,
        },
        value: locklift.utils.convertCrystal(10, 'nano'),
    });

    const pair_address = await dex_root.call({
        method: 'getExpectedPairAddress',
        params: {
            'left_root': left.address,
            'right_root': right.address,
        },
        keyPair: owner.keyPair
    });

    const left_symbol = await left.symbol();
    const right_symbol = await right.symbol();

    const DexPair = await locklift.factory.getContract('DexPair', DEX_CONTRACTS_PATH);
    DexPair.setAddress(pair_address);

    DexPair.name = `Dex Pair [${left_symbol}-${right_symbol}]`;

    await logContract(DexPair);

    const token_roots = await DexPair.call({
        method: 'getTokenRoots',
    });

    const DexPairLp = await locklift.factory.getContract(
        'TokenRoot',
        TOKEN_CONTRACTS_PATH
    );
    DexPairLp.setAddress(token_roots.lp);

    DexPairLp.name = `Dex pair LP root [${left_symbol}-${right_symbol}]`;

    // await logContract(DexPairLp);

    return [DexPair, DexPairLp];
};



class MetricManager {
    constructor(...contracts) {
        this.contracts = contracts;
        this.checkpoints = {};
    }

    lastCheckPointName() {
        return Object.keys(this.checkpoints).pop();
    }

    async checkPoint(name) {
        const balances = await Promise.all(this.contracts.map(async (contract) =>
            locklift.ton.getBalance(contract.address)));

        this.checkpoints[name] = balances;
    }

    getCheckPoint(name) {
        const checkpoint = this.checkpoints[name];

        if (!checkpoint) throw new Error(`No checkpoint "${name}"`);

        return checkpoint;
    }

    async getDifference(startCheckPointName, endCheckPointName) {
        const startCheckPoint = this.getCheckPoint(startCheckPointName);
        const endCheckPoint = this.getCheckPoint(endCheckPointName);

        const difference = {};

        for (const [startMetric, endMetric, contract] of _.zip(startCheckPoint, endCheckPoint, this.contracts)) {
            difference[contract.name] = endMetric - startMetric;
        }

        return difference;
    }

    addContract(contract, fill=0) {
        this.contracts.push(contract);

        for (const checkpoint of Object.keys(this.checkpoints)) {
            this.checkpoints[checkpoint].push(fill);
        }
    }
}


module.exports = {
    expect,
    Token,
    setupFabric,
    afterRun,
    sleep,
    getUserDataDetails,
    setupTokenRoot,
    wait_acc_deployed,
    deployUser,
    calcExpectedReward,
    checkReward,
    FarmPool,
    isValidTonAddress,
    Fabric,
    logContract,
    setupDex,
    deployDexPair,
    DEX_CONTRACTS_PATH,
    MetricManager
};
