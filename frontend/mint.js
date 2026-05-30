import { ethers } from 'ethers';
import { IERC8270ABI } from '@erc-8270/contracts';
import { TRANSFER_TOPIC, getExplorerUrl } from './utils/constants.js'
import { formatAddress, showError, showSuccess } from './utils/ui.js';
import { validateValidatorKey, validateAddress } from './utils/validation.js';
import { waitForTransaction } from './utils/transaction.js';
import { autoConnect, createWalletState, connectWallet } from './utils/wallet.js';

const abi = new ethers.Interface(IERC8270ABI);

const state = createWalletState();

const connectButton = document.getElementById('connectButton');
const walletConnected = document.getElementById('walletConnected');
const walletAddressEl = document.getElementById('walletAddress');
const validatorKeyInput = document.getElementById('validatorKey');
const mintButton = document.getElementById('mintButton');
const statusMessage = document.getElementById('statusMessage');
const txHashEl = document.getElementById('txHash');
const tokenIdEl = document.getElementById('tokenId');
const txStatusEl = document.getElementById('txStatus');

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
            validatorKeyInput.disabled = false;
            mintButton.disabled = false;
        },
        onError: (msg) => showError(statusMessage, msg)
    });
}

function resetWalletState() {
    state.userAddress = null;
    connectButton.style.display = 'block';
    walletConnected.style.display = 'none';
    validatorKeyInput.disabled = true;
    validatorKeyInput.value = '';
    mintButton.disabled = true;
}

async function mintNFT() {
    const validatorKey = validatorKeyInput.value.trim();

    const keyValidation = validateValidatorKey(validatorKey);
    if (!keyValidation.valid) {
        showError(statusMessage, keyValidation.error);
        return;
    }

    if (!state.userAddress || !state.provider) {
        showError(statusMessage, 'Please connect your wallet first');
        return;
    }

    try {
        mintButton.disabled = true;
        mintButton.textContent = 'Minting...';
        txStatusEl.textContent = 'Preparing transaction...';

        const validatorKeyBytes = ethers.getBytes(keyValidation.key);
        const validatorKeyHi = validatorKeyBytes.slice(0, 32);
        const validatorKeyLo = validatorKeyBytes.slice(32);
        const calldata = abi.encodeFunctionData('mint(bytes32, bytes16)', [validatorKeyHi, validatorKeyLo]);

        const tx = {
            from: state.userAddress,
            to: state.currentNetwork.mainAddress,
            data: calldata
        };

        txStatusEl.textContent = 'Waiting for confirmation...';
        const txHash = await state.provider.request({
            method: 'eth_sendTransaction',
            params: [tx]
        });

        txHashEl.textContent = formatAddress(txHash);
        txHashEl.style.cursor = 'pointer';
        txHashEl.onclick = () => window.open(getExplorerUrl(txHash, state.currentNetwork.chainId), '_blank');
        txStatusEl.textContent = 'Pending...';
        txStatusEl.className = 'status-value status-pending';
        showSuccess(statusMessage, `Transaction submitted! Hash: ${formatAddress(txHash)}`);

        const receipt = await waitForTransaction(state.provider, txHash);

        if (receipt.status === '0x1') {
            txStatusEl.textContent = 'Confirmed';
            txStatusEl.className = 'status-value status-active';

            const tokenId = extractTokenIdFromReceipt(receipt);
            if (tokenId) {
                tokenIdEl.textContent = `#${tokenId}`;
                tokenIdEl.style.cursor = 'pointer';
                tokenIdEl.onclick = () => window.location.href = `/?token=${tokenId}`;
                showSuccess(statusMessage, `NFT minted successfully! Token ID: ${tokenId}`);
            } else {
                showSuccess(statusMessage, 'NFT minted successfully!');
            }
        } else {
            txStatusEl.textContent = 'Failed';
            txStatusEl.className = 'status-value status-exited';
            showError(statusMessage, 'Transaction failed');
        }
    } catch (error) {
        console.error('Minting failed:', error);
        txStatusEl.textContent = 'Failed';
        txStatusEl.className = 'status-value status-exited';
        showError(statusMessage, 'Minting failed: ' + error.message);
    } finally {
        mintButton.disabled = false;
        mintButton.textContent = 'Mint NFT';
    }
}

function extractTokenIdFromReceipt(receipt) {
    if (!receipt.logs || receipt.logs.length === 0) return null;

    const transferLog = receipt.logs.find(log =>
        log.topics && log.topics[0] === TRANSFER_TOPIC
    );

    if (transferLog && transferLog.topics.length >= 4) {
        return BigInt(transferLog.topics[3]).toString();
    }

    return null;
}

function updateMintButtonState() {
    const keyValidation = validateValidatorKey(validatorKeyInput.value.trim());
    mintButton.disabled = !keyValidation.valid || !addressValidation.valid || !state.userAddress;
}

connectButton.addEventListener('click', handleConnectWallet);
mintButton.addEventListener('click', mintNFT);
validatorKeyInput.addEventListener('input', updateMintButtonState);
autoConnect(handleConnectWallet);
