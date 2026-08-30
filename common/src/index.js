import { ethers } from 'ethers';
import { NETWORK } from './networks.js';
import { IERC8270ABI } from '@erc-8270/contracts';

export { NETWORK };

export const ERC20ABI = [
    "event Transfer(address indexed from, address indexed to, uint256 value)",
    "event Approval(address indexed owner, address indexed spender, uint256 value)",
    "function balanceOf(address account) external view returns (uint256)",
    "function transfer(address to, uint256 amount) external returns (bool)",
    "function approve(address spender, uint256 amount) external returns (bool)",
    "function transferFrom(address from, address to, uint256 amount) external returns (bool)",
];

export const SBC_DEPOSIT_CONTRACT_ABI = [
    "function withdrawableAmount(address) external view returns (uint256)",
    "function claimWithdrawal(address) external",
];

export function getExplorerUrl(txHash) {
    return NETWORK.explorerUrl ? `${NETWORK.explorerUrl}/tx/${txHash}` : `#${txHash}`;
}

export function makeContract() {
    const provider = new ethers.JsonRpcProvider(NETWORK.rpcUrl);
    return new ethers.Contract(NETWORK.mainAddress, IERC8270ABI, provider);
}

export async function fetchBeaconChainData(validatorPubkey) {
    try {
        const cleanPubkey = validatorPubkey.startsWith('0x') ? validatorPubkey.slice(2) : validatorPubkey;
        const response = await fetch(`${NETWORK.beaconApiUrl}/eth/v1/beacon/states/head/validators/0x${cleanPubkey}`);
        if (!response.ok) return null;

        const result = await response.json();
        if (!result.data) return null;

        const validator = result.data;
        const balanceGwei = BigInt(validator.balance);
        const balance = Number(balanceGwei) / 1e9 / 32;

        const withdrawalCredentials = validator.validator.withdrawal_credentials;
        const withdrawalAddress = '0x' + withdrawalCredentials.slice(-40);
        const withdrawalCredentialsType = withdrawalCredentials.slice(0, 4);

        let status = 'unknown';
        if (validator.status.includes('active')) status = 'active';
        else if (validator.status.includes('pending')) status = 'pending';
        else if (validator.status.includes('exited') || validator.status.includes('withdrawal')) status = 'exited';

        return {
            balance,
            validatorIndex: validator.index,
            status,
            activationEpoch: validator.validator.activation_epoch === '18446744073709551615' ? null : Number(validator.validator.activation_epoch),
            exitEpoch: validator.validator.exit_epoch === '18446744073709551615' ? null : Number(validator.validator.exit_epoch),
            withdrawalAddress,
            withdrawalCredentialsType
        };
    } catch (error) {
        console.warn('Failed to fetch beacon chain data:', error);
        return null;
    }
}

export async function fetchWithdrawalAddress(tokenId) {
    try {
        const contract = makeContract();
        return await contract.withdrawalAddressOf(BigInt(tokenId));
    } catch (error) {
        console.warn('Failed to fetch withdrawal address:', error);
        return null;
    }
}

export async function fetchTokenData(tokenId) {
    try {
        const tokenIdBigInt = BigInt(tokenId);
        const contract = makeContract();

        let expectedWithdrawalAddress = null;
        try {
            expectedWithdrawalAddress = await contract.withdrawalAddressOf(tokenIdBigInt);
        } catch (e) {
            console.warn('Could not fetch withdrawal address:', e);
        }

        const provider = new ethers.JsonRpcProvider(NETWORK.rpcUrl);
        const depositContract = new ethers.Contract(NETWORK.depositsContractAddress, SBC_DEPOSIT_CONTRACT_ABI, provider);
        const gnoToken = new ethers.Contract(NETWORK.gnoTokenAddress, ERC20ABI, provider);

        let nativeBalance = 0;
        try {
            nativeBalance = Number(await provider.getBalance(expectedWithdrawalAddress)) / 1e18;
        } catch (e) {
            console.warn('Could not fetch native balance:', e);
        }

        const executionBalance = Number(
            await depositContract.withdrawableAmount(expectedWithdrawalAddress) +
            await gnoToken.balanceOf(expectedWithdrawalAddress)
        ) / 1e18;
        const secondaryBalance = nativeBalance;

        let validatorKey = null;
        try {
            const [validatorKeyLo, validatorKeyHi] = await contract.validatorKeyOf(tokenIdBigInt);
            validatorKey = ethers.concat([validatorKeyLo, validatorKeyHi]);
        } catch (e) {
            console.warn('Could not fetch validator key:', e);
        }

        let tokenOwner = null;
        try {
            tokenOwner = await contract.ownerOf(tokenIdBigInt);
        } catch (e) {
            console.warn('Could not fetch token owner:', e);
        }

        let beaconData = null;
        if (validatorKey) {
            beaconData = await fetchBeaconChainData(validatorKey);
        }

        return {
            executionBalance,
            secondaryBalance,
            validatorKey,
            beaconData,
            expectedWithdrawalAddress,
            tokenOwner
        };
    } catch (error) {
        console.error('Failed to fetch token data:', error);
        return null;
    }
}