module.exports = {
  compiler: {
    path: '/usr/local/bin/solc-ton-tonlabs-bbbbeca',
  },
  linker: {
    path: '/usr/local/bin/tvm_linker-80e31a5',
  },
  networks: {
    local: {
      ton_client: {
        network: {
          server_address: 'http://localhost/',
        },
      },
      giver: {
        address: '0:841288ed3b55d9cdafa806807f02a0ae0c169aa5edfe88a789a6482429756a94',
        abi: { "ABI version": 1, "functions": [ { "name": "constructor", "inputs": [], "outputs": [] }, { "name": "sendGrams", "inputs": [ {"name":"dest","type":"address"}, {"name":"amount","type":"uint64"} ], "outputs": [] } ], "events": [], "data": [] },
        key: '',
      },
      keys: {
        phrase: '',
        amount: 20,
      }
    },
    main: {
      ton_client: {
        network: {
          server_address: 'https://main.ton.dev'
        }
      },
      giver: {
        address: process.env.BOOSTER_GIVER_ADDRESS,
        abi: { "ABI version": 2, "header": ["pubkey", "time", "expire"], "functions": [ { "name": "constructor", "inputs": [ ], "outputs": [ ] }, { "name": "sendGrams", "inputs": [ {"name":"dest","type":"address"}, {"name":"amount","type":"uint64"} ], "outputs": [ ] }, { "name": "owner", "inputs": [ ], "outputs": [ {"name":"owner","type":"uint256"} ] } ], "data": [ {"key":1,"name":"owner","type":"uint256"} ], "events": [ ] },
        key: process.env.BOOSTER_GIVER_KEY,
      },
      keys: {
        phrase: '',
        amount: 20,
      }
    },
  },
};
