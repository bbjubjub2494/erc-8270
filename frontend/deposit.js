import { ethers } from 'ethers';
import { ERC8270ABI, DepositsABI, DepositsGnoABI } from '@erc-8270/contracts';
import { ERC20_ABI, getExplorerUrl } from './utils/constants.js';
import { formatAddress, showError, showSuccess } from './utils/ui.js';
import { validateHexField } from './utils/validation.js';
import { waitForTransaction, waitForBatch } from './utils/transaction.js';
import { autoConnect, createWalletState, connectWallet, checkWalletCapabilities } from './utils/wallet.js';
import { fetchWithdrawalAddress as commonFetchWithdrawalAddress } from '@erc-8270/common';

const abi = new ethers.Interface(ERC8270ABI);

const state = createWalletState();
let parsedDepositData = null;

const connectButton = document.getElementById('connectButton');
const walletConnected = document.getElementById('walletConnected');
const walletAddressEl = document.getElementById('walletAddress');
const tokenIdInput = document.getElementById('tokenId');
const withdrawalAddressGroup = document.getElementById('withdrawalAddressGroup');
const withdrawalAddressInput = document.getElementById('withdrawalAddress');
const copyWithdrawalAddressButton = document.getElementById('copyWithdrawalAddress');
const depositDataTextarea = document.getElementById('depositData');
const parseButton = document.getElementById('parseButton');
const parsedDataSection = document.getElementById('parsedData');
const depositButton = document.getElementById('depositButton');
const statusMessage = document.getElementById('statusMessage');
const txHashEl = document.getElementById('txHash');
const txStatusEl = document.getElementById('txStatus');
const parsedNetworkEl = document.getElementById('parsedNetwork');
const parsedAmountEl = document.getElementById('parsedAmount');
const parsedSignatureEl = document.getElementById('parsedSignature');
const parsedCompoundingEl = document.getElementById('parsedCompounding');

async function handleConnectWallet() {
    await connectWallet(state, {
        uiElements: {
            connectButton,
            walletConnected,
            walletAddressEl,
            onDisconnect: resetWalletState
        },
        onSuccess: (msg) => {
            showSuccess(statusMessage, msg);
            tokenIdInput.disabled = false;
            depositDataTextarea.disabled = false;
            parseButton.disabled = false;
            copyWithdrawalAddressButton.style.display = 'none';

            const tokenId = tokenIdInput.value.trim();
            if (tokenId) {
                fetchWithdrawalAddress(tokenId);
            }
        },
        onError: (msg) => showError(statusMessage, msg)
    });
}

function resetWalletState() {
    state.userAddress = null;
    connectButton.style.display = 'block';
    walletConnected.style.display = 'none';
    tokenIdInput.disabled = true;
    tokenIdInput.value = '';
    depositDataTextarea.disabled = true;
    depositDataTextarea.value = '';
    parseButton.disabled = true;
    depositButton.style.display = 'none';
    parsedDataSection.style.display = 'none';
    withdrawalAddressGroup.style.display = 'none';
    copyWithdrawalAddressButton.style.display = 'none';
    parsedDepositData = null;
}

function parseDepositData() {
    const jsonText = depositDataTextarea.value.trim();

    if (!jsonText) {
        showError(statusMessage, 'Please paste deposit data JSON');
        return;
    }

    try {
        const data = JSON.parse(jsonText);
        const depositItem = Array.isArray(data) ? data[0] : data;

        if (!depositItem) {
            showError(statusMessage, 'Deposit data is empty');
            return;
        }

        const requiredFields = ['pubkey', 'signature', 'deposit_data_root', 'amount', 'network_name'];
        for (const field of requiredFields) {
            if (!depositItem[field]) {
                showError(statusMessage, `Missing required field: ${field}`);
                return;
            }
        }

        const expectedNetworkName = state.id;
        if (depositItem.network_name.toLowerCase() !== expectedNetworkName) {
            showError(statusMessage, `Invalid network: ${depositItem.network_name}. Expected "${expectedNetworkName}"`);
            return;
        }

        const pubkey = validateHexField(depositItem.pubkey, 96, 'pubkey');
        if (!pubkey.valid) {
            showError(statusMessage, pubkey.error);
            return;
        }

        const signature = validateHexField(depositItem.signature, 192, 'signature');
        if (!signature.valid) {
            showError(statusMessage, signature.error);
            return;
        }

        const depositDataRoot = validateHexField(depositItem.deposit_data_root, 64, 'deposit_data_root');
        if (!depositDataRoot.valid) {
            showError(statusMessage, depositDataRoot.error);
            return;
        }

        const amount = BigInt(depositItem.amount);
        if (amount <= 0n) {
            showError(statusMessage, 'Amount must be greater than 0');
            return;
        }

        const withdrawalCredentials = depositItem.withdrawal_credentials;
        if (!withdrawalCredentials) {
            showError(statusMessage, 'Missing withdrawal_credentials field');
            return;
        }

        const firstByte = withdrawalCredentials.startsWith('0x')
            ? withdrawalCredentials.slice(2, 4)
            : withdrawalCredentials.slice(0, 2);

        const isCompounding = firstByte === '02';
        const isNonCompounding = firstByte === '01';

        if (!isCompounding && !isNonCompounding) {
            showError(statusMessage, `Invalid withdrawal credentials prefix: 0x${firstByte}. Must be 0x01 (non-compounding) or 0x02 (compounding)`);
            return;
        }

        parsedDepositData = {
            pubkey: pubkey.value,
            signature: signature.value,
            depositDataRoot: depositDataRoot.value,
            amount: amount,
            networkName: depositItem.network_name,
            withdrawalCredentials: withdrawalCredentials,
            isCompounding: isCompounding
        };

        parsedNetworkEl.textContent = parsedDepositData.networkName;
        parsedAmountEl.textContent = `${Number(amount) / (state.currentNetwork.isGno ? 32 : 1) / 1e9} ${state.currentNetwork.currency}`;
        parsedSignatureEl.textContent = formatAddress(parsedDepositData.signature);
        parsedCompoundingEl.textContent = isCompounding ? 'Yes' : 'No';

        parsedDataSection.style.display = 'block';
        depositButton.style.display = 'block';
        depositButton.disabled = !tokenIdInput.value.trim();

        showSuccess(statusMessage, 'Deposit data parsed successfully!');
    } catch (error) {
        console.error('Failed to parse deposit data:', error);
        showError(statusMessage, 'Failed to parse deposit data: ' + error.message);
    }
}

async function deposit() {
    if (!parsedDepositData) {
        showError(statusMessage, 'Please parse deposit data first');
        return;
    }

    const tokenId = tokenIdInput.value.trim();
    if (!tokenId) {
        showError(statusMessage, 'Please enter a token ID');
        return;
    }

    if (!state.userAddress || !state.provider) {
        showError(statusMessage, 'Please connect your wallet first');
        return;
    }

    try {
        depositButton.disabled = true;
        depositButton.textContent = 'Depositing...';
        txStatusEl.textContent = 'Preparing transaction...';

        const tokenIdBigInt = BigInt(tokenId);
        const compounding = parsedDepositData.isCompounding;
        let amountInWei = parsedDepositData.amount * 1000000000n;
        amountInWei /= state.currentNetwork.isGno ? 32n : 1n;

        if (state.currentNetwork.isGno) {
            const supportsBatching = await checkWalletCapabilities(state.provider, state.userAddress, state.currentNetwork.chainId);
            if (supportsBatching) {
                await depositWithBatchingERC20(tokenIdBigInt, compounding, amountInWei);
            } else {
                await depositWithoutBatchingERC20(tokenIdBigInt, compounding, amountInWei);
            }
        } else {
            await depositPayable(tokenIdBigInt, compounding, amountInWei);
        }
    } catch (error) {
        console.error('Deposit failed:', error);
        txStatusEl.textContent = 'Failed';
        txStatusEl.className = 'status-value status-exited';
        showError(statusMessage, 'Deposit failed: ' + error.message);
    } finally {
        depositButton.disabled = false;
        depositButton.textContent = 'Deposit to Validator';
    }
}

async function approveToken(amount) {
    const erc20Iface = new ethers.Interface(ERC20_ABI);
    const depositsAddress = state.currentNetwork.depositsAddress;
    const tokenAddress = state.currentNetwork.gnoTokenAddress;
    const approveCalldata = erc20Iface.encodeFunctionData('approve', [depositsAddress, amount]);

    const tx = {
        from: state.userAddress,
        to: tokenAddress,
        data: approveCalldata
    };

    const txHash = await state.provider.request({
        method: 'eth_sendTransaction',
        params: [tx]
    });

    return txHash;
}

async function depositWithBatchingERC20(tokenIdBigInt, compounding, amountInWei) {
    txStatusEl.textContent = 'Preparing batched transaction...';
    showSuccess(statusMessage, 'Using EIP-5792 batching for single signature approval!');

    const erc20Iface = new ethers.Interface(ERC20_ABI);
    const depositsIface = new ethers.Interface(IDepositsGnoABI);
    const depositsAddress = state.currentNetwork.depositsAddress;
    const tokenAddress = state.currentNetwork.gnoTokenAddress;
    const approveCalldata = erc20Iface.encodeFunctionData('approve', [depositsAddress, amountInWei]);

    const signatureBytes = ethers.getBytes(parsedDepositData.signature);
    const depositDataRootBytes = ethers.getBytes(parsedDepositData.depositDataRoot);
    const depositCalldata = depositsIface.encodeFunctionData('frontrunnable', [
        tokenIdBigInt,
        compounding,
        signatureBytes,
        depositDataRootBytes,
        amountInWei
    ]);

    const calls = [
        { to: tokenAddress, data: approveCalldata, value: '0x0' },
        { to: depositsAddress, data: depositCalldata, value: '0x0' }
    ];

    txStatusEl.textContent = 'Waiting for signature...';
    showSuccess(statusMessage, 'Please sign the batched transaction...');

    const batchId = await state.provider.request({
        method: 'wallet_sendCalls',
        params: [{
            version: '1.0',
            chainId: '0x' + state.currentNetwork.chainId.toString(16),
            from: state.userAddress,
            calls: calls
        }]
    });

    txHashEl.textContent = formatAddress(batchId);
    txStatusEl.textContent = 'Batch submitted...';
    txStatusEl.className = 'status-value status-pending';
    showSuccess(statusMessage, `Batch submitted! ID: ${formatAddress(batchId)}`);

    txStatusEl.textContent = 'Waiting for confirmation...';
    await waitForBatch(state.provider, batchId);

    txStatusEl.textContent = 'Confirmed';
    txStatusEl.className = 'status-value status-active';
    showSuccess(statusMessage, 'Deposit successful! Your validator is now being activated.');
}

async function depositWithoutBatchingERC20(tokenIdBigInt, compounding, amountInWei) {
    showSuccess(statusMessage, 'Wallet does not support EIP-5792 batching. Using two-step process...');

    txStatusEl.textContent = `Approving ${state.currentNetwork.currency} token...`;
    showSuccess(statusMessage, `Approving ${state.currentNetwork.currency} token spending...`);

    const approveTxHash = await approveToken(amountInWei);
    showSuccess(statusMessage, `Approval submitted! Hash: ${formatAddress(approveTxHash)}`);

    txStatusEl.textContent = 'Waiting for approval confirmation...';
    await waitForTransaction(state.provider, approveTxHash);
    showSuccess(statusMessage, `${state.currentNetwork.currency} token approved successfully!`);

    txStatusEl.textContent = 'Preparing deposit...';

    const depositsIface = new ethers.Interface(IDepositsGnoABI);
    const signatureBytes = ethers.getBytes(parsedDepositData.signature);
    const depositDataRootBytes = ethers.getBytes(parsedDepositData.depositDataRoot);
    const calldata = depositsIface.encodeFunctionData('frontrunnable', [
        tokenIdBigInt,
        compounding,
        signatureBytes,
        depositDataRootBytes,
        amountInWei
    ]);

    const depositsAddress = state.currentNetwork.depositsAddress;
    const tx = {
        from: state.userAddress,
        to: depositsAddress,
        data: calldata
    };

    txStatusEl.textContent = 'Waiting for confirmation...';
    showSuccess(statusMessage, 'Please confirm the deposit transaction...');

    const txHash = await state.provider.request({
        method: 'eth_sendTransaction',
        params: [tx]
    });

    txHashEl.textContent = formatAddress(txHash);
    txHashEl.style.cursor = 'pointer';
    txHashEl.onclick = () => window.open(getExplorerUrl(txHash, state.currentNetwork.chainId), '_blank');
    txStatusEl.textContent = 'Pending...';
    txStatusEl.className = 'status-value status-pending';
    showSuccess(statusMessage, `Deposit transaction submitted! Hash: ${formatAddress(txHash)}`);

    const receipt = await waitForTransaction(state.provider, txHash);

    if (receipt.status === '0x1') {
        txStatusEl.textContent = 'Confirmed';
        txStatusEl.className = 'status-value status-active';
        showSuccess(statusMessage, 'Deposit successful! Your validator is now being activated.');
    } else {
        txStatusEl.textContent = 'Failed';
        txStatusEl.className = 'status-value status-exited';
        showError(statusMessage, 'Transaction failed');
    }
}

async function depositPayable(tokenIdBigInt, compounding, amountInWei) {
    showSuccess(statusMessage, 'Using native ETH deposit (no approval needed)...');

    txStatusEl.textContent = 'Preparing deposit...';

    const depositsIface = new ethers.Interface(IDepositsABI);
    const signatureBytes = ethers.getBytes(parsedDepositData.signature);
    const depositDataRootBytes = ethers.getBytes(parsedDepositData.depositDataRoot);
    const calldata = depositsIface.encodeFunctionData('frontrunnable', [
        tokenIdBigInt,
        compounding,
        signatureBytes,
        depositDataRootBytes
    ]);

    const depositsAddress = state.currentNetwork.depositsAddress;
    const tx = {
        from: state.userAddress,
        to: depositsAddress,
        data: calldata,
        value: '0x' + amountInWei.toString(16)
    };

    txStatusEl.textContent = 'Waiting for confirmation...';
    showSuccess(statusMessage, 'Please confirm the deposit transaction...');

    const txHash = await state.provider.request({
        method: 'eth_sendTransaction',
        params: [tx]
    });

    txHashEl.textContent = formatAddress(txHash);
    txHashEl.style.cursor = 'pointer';
    txHashEl.onclick = () => window.open(getExplorerUrl(txHash, state.currentNetwork.chainId), '_blank');
    txStatusEl.textContent = 'Pending...';
    txStatusEl.className = 'status-value status-pending';
    showSuccess(statusMessage, `Deposit transaction submitted! Hash: ${formatAddress(txHash)}`);

    const receipt = await waitForTransaction(state.provider, txHash);

    if (receipt.status === '0x1') {
        txStatusEl.textContent = 'Confirmed';
        txStatusEl.className = 'status-value status-active';
        showSuccess(statusMessage, 'Deposit successful! Your validator is now being activated.');
    } else {
        txStatusEl.textContent = 'Failed';
        txStatusEl.className = 'status-value status-exited';
        showError(statusMessage, 'Transaction failed');
    }
}

async function fetchWithdrawalAddress(tokenId) {
    try {
        withdrawalAddressGroup.style.display = 'block';
        withdrawalAddressInput.value = 'Loading...';

        const address = await commonFetchWithdrawalAddress(state.currentNetwork, tokenId);
        if (!address) {
            throw new Error('No address returned');
        }

        const checksummedAddress = ethers.getAddress(address);
        withdrawalAddressInput.value = checksummedAddress;
        copyWithdrawalAddressButton.style.display = 'block';
    } catch (error) {
        console.error('Failed to fetch withdrawal address:', error);
        withdrawalAddressInput.value = 'Error fetching address';
        withdrawalAddressGroup.style.display = 'none';
    }
}

copyWithdrawalAddressButton.addEventListener('click', async () => {
    try {
        await navigator.clipboard.writeText(withdrawalAddressInput.value);
        const originalText = copyWithdrawalAddressButton.textContent;
        copyWithdrawalAddressButton.textContent = '✓';
        setTimeout(() => {
            copyWithdrawalAddressButton.textContent = originalText;
        }, 2000);
    } catch (error) {
        console.error('Failed to copy to clipboard:', error);
    }
});

function loadTokenFromURL() {
    const params = new URLSearchParams(window.location.search);
    const tokenId = params.get('token');
    if (tokenId) {
        tokenIdInput.value = tokenId;
    }
}

connectButton.addEventListener('click', handleConnectWallet);
parseButton.addEventListener('click', parseDepositData);
depositButton.addEventListener('click', deposit);

tokenIdInput.addEventListener('input', async () => {
    if (parsedDepositData && tokenIdInput.value.trim()) {
        depositButton.disabled = false;
    } else {
        depositButton.disabled = true;
    }

    const tokenId = tokenIdInput.value.trim();
    if (tokenId && state.userAddress && state.provider) {
        await fetchWithdrawalAddress(tokenId);
    } else {
        withdrawalAddressGroup.style.display = 'none';
    }
});

autoConnect(handleConnectWallet);
loadTokenFromURL();
