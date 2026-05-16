import { getExplorerUrl as commonGetExplorerUrl } from '@erc-xxxx/common';

export const ERC20_ABI = [
    {
        "inputs": [
            {"internalType": "address", "name": "spender", "type": "address"},
            {"internalType": "uint256", "name": "amount", "type": "uint256"}
        ],
        "name": "approve",
        "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
        "stateMutability": "nonpayable",
        "type": "function"
    }
];

export const TRANSFER_TOPIC = '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef';

export function getExplorerUrl(txHash, chainId, network) {
    if (network?.explorerUrl) {
        return commonGetExplorerUrl(network, txHash);
    }
    return `#${txHash}`;
}
