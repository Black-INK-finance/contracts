const {logContract} = require("../../test/utils");
const main = async () => {
    const payload = 'te6ccgEBAwEAMwACUgEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHgvSAgEAASAAAaA=';

    const CellEncoder = await locklift.factory.getContract('CellEncoder');

    const encoder = await locklift.giver.deployContract({
        contract: CellEncoder
    });

    await logContract(encoder);

    const decoded = await encoder.call({
        method: 'decodeSwapPayload',
        params: {
            payload
        }
    });

    console.log(decoded);

    console.log(decoded.expected_amount.toString());
};


main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });


