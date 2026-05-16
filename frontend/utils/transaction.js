export async function waitForTransaction(provider, txHash, maxAttempts = 60) {
    for (let i = 0; i < maxAttempts; i++) {
        try {
            const receipt = await provider.request({
                method: 'eth_getTransactionReceipt',
                params: [txHash]
            });

            if (receipt) {
                return receipt;
            }
        } catch (error) {
            console.warn('Error fetching receipt:', error);
        }

        await new Promise(resolve => setTimeout(resolve, 2000));
    }

    throw new Error('Transaction confirmation timeout');
}

export async function waitForBatch(provider, batchId, maxAttempts = 60) {
    for (let i = 0; i < maxAttempts; i++) {
        try {
            const status = await provider.request({
                method: 'wallet_getCallsStatus',
                params: [batchId]
            });

            if (status.status === 'CONFIRMED') {
                return status;
            } else if (status.status === 'FAILED') {
                throw new Error('Batch transaction failed');
            }
        } catch (error) {
            console.warn('Error fetching batch status:', error);
        }

        await new Promise(resolve => setTimeout(resolve, 2000));
    }

    throw new Error('Batch confirmation timeout');
}
