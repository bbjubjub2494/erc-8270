import { NETWORK } from '@erc-8270/common';

export function autoConnect(connectWallet) {
    if (typeof window.ethereum !== 'undefined') {
        window.ethereum.request({ method: 'eth_accounts' })
            .then(accounts => {
                if (accounts.length > 0) {
                    connectWallet();
                }
            })
            .catch(console.error);
    }
}

export function createWalletState() {
    return {
        userAddress: null,
        provider: null
    };
}

export async function connectWallet(state, { onSuccess, onError, uiElements }) {
    const { connectButton, walletConnected, walletAddressEl } = uiElements;

    if (typeof window.ethereum === 'undefined') {
        onError?.('MetaMask is not installed. Please install MetaMask to continue.');
        return;
    }

    try {
        const accounts = await window.ethereum.request({
            method: 'eth_requestAccounts'
        });

        state.userAddress = accounts[0];
        state.provider = window.ethereum;

        connectButton.style.display = 'none';
        walletConnected.style.display = 'flex';
        walletAddressEl.textContent = formatAddress(state.userAddress);

        onSuccess?.(`Wallet connected to ${NETWORK.name} (${NETWORK.currency})!`);

        state.provider.on('accountsChanged', (accounts) => handleAccountsChanged(state, accounts, uiElements));
        state.provider.on('chainChanged', () => window.location.reload());
    } catch (error) {
        console.error('Failed to connect wallet:', error);
        onError?.('Failed to connect wallet: ' + error.message);
    }
}

function handleAccountsChanged(state, accounts, uiElements) {
    const { walletAddressEl, onDisconnect } = uiElements;

    if (accounts.length === 0) {
        state.userAddress = null;
        onDisconnect?.();
    } else {
        state.userAddress = accounts[0];
        walletAddressEl.textContent = formatAddress(state.userAddress);
    }
}

function formatAddress(address) {
    return `${address.substring(0, 6)}...${address.substring(address.length - 4)}`;
}

export async function checkWalletCapabilities(provider, userAddress) {
    try {
        const capabilities = await provider.request({
            method: 'wallet_getCapabilities',
            params: [userAddress]
        });
        const chainIdHex = '0x' + NETWORK.chainId.toString(16);
        return capabilities?.[chainIdHex]?.atomicBatch?.supported === true;
    } catch (error) {
        console.warn('wallet_getCapabilities not supported:', error);
        return false;
    }
}
