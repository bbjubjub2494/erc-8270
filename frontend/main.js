import { ethers } from 'ethers';
import { ERCXXXXABI, DepositsABI, DepositsGnoABI } from '@erc-xxxx/contracts';
import { fetchBeaconChainData as commonFetchBeaconChainData, fetchTokenData as commonFetchTokenData, NETWORKS, SBC_DEPOSIT_CONTRACT_ABI, ERC20ABI } from '@erc-xxxx/common';
import { waitForTransaction, waitForBatch } from './utils/transaction.js';

let currentNetwork = NETWORKS.chiado;

const provider = {
    async request({ method, params }) {
        return this.requestUrl(currentNetwork.rpcUrl, { method, params });
    },
    async requestL1({ method, params }) {
        return this.requestUrl(currentNetwork.l1RpcUrl, { method, params });
    },
    async requestUrl(url, { method, params }) {
        const response = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                jsonrpc: '2.0',
                method,
                params,
                id: 1
            })
        });
        const result = await response.json();
        if (result.error) {
            throw new Error(result.error.message);
        }
        return result.result;
    }
};

async function fetchBeaconChainData(validatorPubkey) {
    const beaconData = await commonFetchBeaconChainData(currentNetwork, validatorPubkey);
    if (!beaconData) return null;

    return {
        balance: beaconData.balance,
        validatorIndex: beaconData.validatorIndex,
        status: beaconData.status,
        activationEpoch: beaconData.activationEpoch === null ? '-' : beaconData.activationEpoch.toLocaleString(),
        exitEpoch: beaconData.exitEpoch === null ? '-' : beaconData.exitEpoch.toLocaleString(),
        withdrawalAddress: beaconData.withdrawalAddress,
        withdrawalCredentialsType: beaconData.withdrawalCredentialsType
    };
}

async function fetchOnChainData(tokenId) {
    const tokenData = await commonFetchTokenData(currentNetwork, tokenId);
    if (!tokenData) return null;

    let validatorKey = tokenData.validatorKey;
    if (validatorKey && validatorKey.length > 0) {
        validatorKey = ethers.hexlify(validatorKey);
    } else {
        validatorKey = "0x0000...0000";
    }

    let beaconData = null;
    if (validatorKey && validatorKey !== "0x0000...0000") {
        beaconData = await fetchBeaconChainData(validatorKey);
    }

    const consensusBalance = beaconData ? beaconData.balance.toPrecision(6) : 0;
    const validatorState = beaconData ? beaconData.status : "unknown";
    const validatorIndex = beaconData ? `#${beaconData.validatorIndex}` : `-`;
    const activationEpoch = beaconData ? beaconData.activationEpoch : "-";
    const exitEpoch = beaconData ? beaconData.exitEpoch : "-";

    return {
        executionBalance: tokenData.executionBalance.toPrecision(6),
        secondaryBalance: tokenData.secondaryBalance.toPrecision(6),
        consensusBalance: consensusBalance,
        validatorPubkey: validatorKey,
        validatorState: validatorState,
        validatorIndex: validatorIndex,
        activationEpoch: activationEpoch,
        exitEpoch: exitEpoch,
        expectedWithdrawalAddress: tokenData.expectedWithdrawalAddress,
        beaconWithdrawalAddress: beaconData ? beaconData.withdrawalAddress : null,
        withdrawalCredentialsType: beaconData ? beaconData.withdrawalCredentialsType : null,
        tokenOwner: tokenData.tokenOwner
    };
}

function updateDepositLink(tokenId) {
    const depositLink = document.getElementById('depositLink');
    if (depositLink) {
        const networkName = Object.keys(NETWORKS).find(key => NETWORKS[key] === currentNetwork) || 'chiado';
        depositLink.href = `/deposit.html?token=${tokenId}&network=${networkName}`;
    }
}

async function updateTokenDisplay(tokenId) {
    document.getElementById('executionBalance').textContent = 'Loading...';
    document.getElementById('consensusBalance').textContent = 'Loading...';
    document.getElementById('tokenId').textContent = tokenId;

    updateDepositLink(tokenId);

    const onChainData = await fetchOnChainData(tokenId);
    const data = onChainData || {
        executionBalance: "0.000000",
        secondaryBalance: "0.000000",
        consensusBalance: "0.000000",
        validatorPubkey: "0x0000...0000",
        validatorState: "unknown",
        validatorIndex: "#------",
        activationEpoch: "-",
        exitEpoch: "-",
        expectedWithdrawalAddress: null,
        beaconWithdrawalAddress: null,
        withdrawalCredentialsType: null,
        tokenOwner: null
    };

    document.getElementById('executionBalance').textContent = data.executionBalance;
    document.getElementById('consensusBalance').textContent = data.consensusBalance;
    document.getElementById('validatorPubkey').textContent = data.validatorPubkey.substring(0, 10) + '...' + data.validatorPubkey.substring(data.validatorPubkey.length - 4);
    document.getElementById('validatorIndex').textContent = data.validatorIndex;
    document.getElementById('activationEpoch').textContent = data.activationEpoch;
    document.getElementById('exitEpoch').textContent = data.exitEpoch;

    const tokenOwnerElement = document.getElementById('tokenOwner');
    if (data.tokenOwner) {
        const shortOwner = data.tokenOwner.substring(0, 6) + '...' + data.tokenOwner.substring(data.tokenOwner.length - 4);
        tokenOwnerElement.textContent = shortOwner;
    } else {
        tokenOwnerElement.textContent = '-';
    }

    const secondaryBalanceContainer = document.getElementById('secondaryBalanceContainer');
    const secondaryBalanceElement = document.getElementById('secondaryBalance');
    const secondaryBalanceValue = parseFloat(data.secondaryBalance);
    
    if (secondaryBalanceValue > 0) {
        secondaryBalanceElement.textContent = data.secondaryBalance;
        secondaryBalanceContainer.style.display = 'block';
    } else {
        secondaryBalanceContainer.style.display = 'none';
    }

    const statusElement = document.getElementById('validatorState');
    statusElement.textContent = data.validatorState.charAt(0).toUpperCase() + data.validatorState.slice(1);
    statusElement.className = 'status-value status-' + data.validatorState;

    const withdrawalAddressElement = document.getElementById('withdrawalAddress');
    const withdrawalWarningElement = document.getElementById('withdrawalWarning');
    const withdrawalWarningDetails = document.getElementById('withdrawalWarningDetails');
    const withdrawalNotSetElement = document.getElementById('withdrawalNotSet');

    withdrawalWarningElement.style.display = 'none';
    withdrawalNotSetElement.style.display = 'none';
    withdrawalAddressElement.style.color = '';

    if (!data.beaconWithdrawalAddress) {
        withdrawalAddressElement.textContent = 'Not set';
        withdrawalAddressElement.style.color = '#f59e0b';
        withdrawalNotSetElement.style.display = 'block';
    } else if (data.withdrawalCredentialsType === '0x00') {
        withdrawalAddressElement.textContent = 'Not set (BLS)';
        withdrawalAddressElement.style.color = '#f59e0b';
        withdrawalNotSetElement.style.display = 'block';
    } else {
        const shortAddr = data.beaconWithdrawalAddress.substring(0, 6) + '...' + data.beaconWithdrawalAddress.substring(data.beaconWithdrawalAddress.length - 4);
        withdrawalAddressElement.textContent = shortAddr;

        if (data.expectedWithdrawalAddress &&
            data.beaconWithdrawalAddress.toLowerCase() !== data.expectedWithdrawalAddress.toLowerCase()) {
            withdrawalAddressElement.style.color = '#ef4444';
            withdrawalWarningDetails.innerHTML =
                'Beacon: <code>' + data.beaconWithdrawalAddress + '</code><br>' +
                'Expected: <code>' + data.expectedWithdrawalAddress + '</code>';
            withdrawalWarningElement.style.display = 'block';
        }
    }

    const switchToCompoundingButton = document.getElementById('switchToCompoundingButton');
    if (data.withdrawalCredentialsType === '0x01') {
        switchToCompoundingButton.style.display = 'inline-block';
    } else {
        switchToCompoundingButton.style.display = 'none';
    }

    document.querySelectorAll('.balance-unit').forEach(el => {
        el.textContent = currentNetwork.currency;
    });
}

async function navigateToToken() {
    const tokenId = document.getElementById('tokenInput').value.trim();
    if (tokenId) {
        try {
            const tokenIdBigInt = BigInt(tokenId);
            if (tokenIdBigInt > 0n) {
                await updateTokenDisplay(tokenId);
                history.pushState(null, '', `?token=${tokenId}`);
            } else {
                alert('Token ID must be greater than 0');
            }
        } catch (error) {
            alert('Invalid token ID. Please enter a valid number.');
        }
    }
}

async function loadTokenFromURL() {
    const params = new URLSearchParams(window.location.search);

    const networkParam = params.get('network');
    if (networkParam && NETWORKS[networkParam.toLowerCase()]) {
        currentNetwork = NETWORKS[networkParam.toLowerCase()];
    }

    const tokenId = params.get('token');
    if (tokenId) {
        try {
            const tokenIdBigInt = BigInt(tokenId);
            if (tokenIdBigInt > 0n) {
                document.getElementById('tokenInput').value = tokenId;
            }
        } catch (error) {
            console.warn('Invalid token ID in URL:', tokenId);
        }
                await updateTokenDisplay(tokenId);
    } else {
        document.querySelectorAll('.balance-unit').forEach(el => {
            el.textContent = currentNetwork.currency;
        });
    }
}

window.addEventListener('popstate', () => loadTokenFromURL());

document.getElementById('tokenInput').addEventListener('keypress', function(e) {
    if (e.key === 'Enter') {
        navigateToToken();
    }
});

async function pullExecutionLayerBalance() {
    const tokenId = document.getElementById('tokenInput').value.trim();
    const button = document.getElementById('pullExecutionLayerBalanceButton');
    
    const iface = new ethers.Interface(ERCXXXXABI);

    if (!tokenId) {
        alert('Please enter a token ID first');
        return;
    }
    
    try {
        const tokenIdBigInt = BigInt(tokenId);
        if (tokenIdBigInt <= 0n) {
            alert('Token ID must be greater than 0');
            return;
        }
        
        if (typeof window.ethereum === 'undefined') {
            alert('Please install a Web3 wallet (e.g., MetaMask) to claim tokens');
            return;
        }
        
        button.disabled = true;
        button.textContent = 'Pulling...';
        
        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
        if (!accounts || accounts.length === 0) {
            throw new Error('No accounts found');
        }
        
        const userAddress = accounts[0];
        
        await window.ethereum.request({
            method: 'wallet_switchEthereumChain',
            params: [{ chainId: `0x${currentNetwork.chainId.toString(16)}` }]
        });
        
        if (currentNetwork.isGno) {
            const sbcIface = new ethers.Interface(SBC_DEPOSIT_CONTRACT_ABI);
            const erc20Iface = new ethers.Interface(ERC20ABI);

            const withdrawalAddressRaw = await provider.request({
                method: 'eth_call',
                params: [{ to: currentNetwork.mainAddress, data: iface.encodeFunctionData('withdrawalAddressOf(uint256)', [tokenIdBigInt]) }, 'latest']
            });
            const withdrawalAddress = iface.decodeFunctionResult('withdrawalAddressOf(uint256)', withdrawalAddressRaw)[0];

            const [withdrawableRaw, gnoBalanceRaw] = await Promise.all([
                provider.request({ method: 'eth_call', params: [{ to: currentNetwork.depositsContractAddress, data: sbcIface.encodeFunctionData('withdrawableAmount', [withdrawalAddress]) }, 'latest'] }),
                provider.request({ method: 'eth_call', params: [{ to: currentNetwork.gnoTokenAddress, data: erc20Iface.encodeFunctionData('balanceOf', [withdrawalAddress]) }, 'latest'] }),
            ]);
            const totalAmount = BigInt(withdrawableRaw) + BigInt(gnoBalanceRaw);

            const claimData = sbcIface.encodeFunctionData('claimWithdrawal', [withdrawalAddress]);
            const transferData = erc20Iface.encodeFunctionData('transfer', [userAddress, totalAmount]);
            const arbitraryCallData = iface.encodeFunctionData(iface.getFunction('arbitraryCall(uint256,address,bytes)'), [tokenIdBigInt, currentNetwork.gnoTokenAddress, transferData]);

            const batchId = await window.ethereum.request({
                method: 'wallet_sendCalls',
                params: [{
                    version: '1.0',
                    chainId: '0x' + currentNetwork.chainId.toString(16),
                    from: userAddress,
                    calls: [
                        { to: currentNetwork.depositsContractAddress, data: claimData, value: '0x0' },
                        { to: currentNetwork.mainAddress, data: arbitraryCallData, value: '0x0' }
                    ]
                }]
            });

            button.textContent = 'Waiting...';
            await waitForBatch(window.ethereum, batchId);
            alert(`Batch confirmed! ID: ${batchId}`);
        } else {
            const fn = iface.getFunction('pullNativeBalance(uint256)');
            const pullCallData = iface.encodeFunctionData(fn, [tokenIdBigInt]);

            const txHash = await window.ethereum.request({
                method: 'eth_sendTransaction',
                params: [{ to: currentNetwork.mainAddress, data: pullCallData, from: userAddress }]
            });

            alert(`Transaction sent! Hash: ${txHash}\nPlease wait for confirmation.`);
        }

        setTimeout(async () => {
            await updateTokenDisplay(tokenId);
            button.disabled = false;
            button.textContent = 'Pull';
        }, 5000);
        
    } catch (error) {
        console.error('Error pulling balance:', error);
        alert(`Error pulling balance: ${error.message}`);
        button.disabled = false;
        button.textContent = 'Pull';
    }
}

async function pullNative() {
    const tokenId = document.getElementById('tokenInput').value.trim();
    const button = document.getElementById('claimNativeButton');
    
    const iface = new ethers.Interface(ERCXXXXABI);

    if (!tokenId) {
        alert('Please enter a token ID first');
        return;
    }
    
    try {
        const tokenIdBigInt = BigInt(tokenId);
        if (tokenIdBigInt <= 0n) {
            alert('Token ID must be greater than 0');
            return;
        }
        
        if (typeof window.ethereum === 'undefined') {
            alert('Please install a Web3 wallet (e.g., MetaMask) to pull native tokens');
            return;
        }
        
        button.disabled = true;
        button.textContent = 'Pull XDAI...';
        
        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
        if (!accounts || accounts.length === 0) {
            throw new Error('No accounts found');
        }
        
        const userAddress = accounts[0];
        
        await window.ethereum.request({
            method: 'wallet_switchEthereumChain',
            params: [{ chainId: `0x${currentNetwork.chainId.toString(16)}` }]
        });
        
        const pullNativeCallData = iface.encodeFunctionData('pullNative', [tokenIdBigInt, userAddress]);
        
        const transaction = {
            to: currentNetwork.mainAddress,
            data: pullNativeCallData,
            from: userAddress
        };
        
        const txHash = await window.ethereum.request({
            method: 'eth_sendTransaction',
            params: [transaction]
        });
        
        alert(`Transaction sent! Hash: ${txHash}\nPlease wait for confirmation.`);
        
        setTimeout(async () => {
            await updateTokenDisplay(tokenId);
            pullNativeButton.disabled = false;
            pullNativeButton.textContent = 'Pull XDAI';
        }, 5000);
        
    } catch (error) {
        console.error('Error pulling XDAI:', error);
        alert(`Error pulling XDAI: ${error.message}`);
        pullNativeButton.disabled = false;
        pullNativeButton.textContent = 'Pull XDAI';
    }
}

async function requestFullWithdrawal() {
    const tokenId = document.getElementById('tokenInput').value.trim();
    const withdrawalButton = document.getElementById('requestWithdrawalButton');

    const iface = new ethers.Interface(ERCXXXXABI);

    if (!tokenId) {
        alert('Please enter a token ID first');
        return;
    }

    try {
        const tokenIdBigInt = BigInt(tokenId);
        if (tokenIdBigInt <= 0n) {
            alert('Token ID must be greater than 0');
            return;
        }

        if (typeof window.ethereum === 'undefined') {
            alert('Please install a Web3 wallet (e.g., MetaMask) to request withdrawal');
            return;
        }

        withdrawalButton.disabled = true;
        withdrawalButton.textContent = 'Requesting...';

        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
        if (!accounts || accounts.length === 0) {
            throw new Error('No accounts found');
        }

        const userAddress = accounts[0];

        await window.ethereum.request({
            method: 'wallet_switchEthereumChain',
            params: [{ chainId: `0x${currentNetwork.chainId.toString(16)}` }]
        });

        const withdrawalCallData = iface.encodeFunctionData('requestFullWithdrawal', [tokenIdBigInt]);

        const transaction = {
            to: currentNetwork.mainAddress,
            data: withdrawalCallData,
            from: userAddress,
            value: '1000000000'
        };

        const txHash = await window.ethereum.request({
            method: 'eth_sendTransaction',
            params: [transaction]
        });

        alert(`Withdrawal request sent! Hash: ${txHash}\nThe validator will exit and funds will be available after the exit is processed.`);

        setTimeout(async () => {
            await updateTokenDisplay(tokenId);
            withdrawalButton.disabled = false;
            withdrawalButton.textContent = 'Request Full Withdrawal';
        }, 5000);

    } catch (error) {
        console.error('Error requesting withdrawal:', error);
        alert(`Error requesting withdrawal: ${error.message}`);
        withdrawalButton.disabled = false;
        withdrawalButton.textContent = 'Request Full Withdrawal';
    }
}

async function requestPartialWithdrawal() {
    const tokenId = document.getElementById('tokenInput').value.trim();
    const amountInput = document.getElementById('partialAmountInput').value.trim();
    const partialButton = document.getElementById('requestPartialButton');

    const iface = new ethers.Interface(ERCXXXXABI);

    if (!tokenId) {
        alert('Please enter a token ID first');
        return;
    }

    if (!amountInput) {
        alert('Please enter an amount to withdraw');
        return;
    }

    try {
        const tokenIdBigInt = BigInt(tokenId);
        if (tokenIdBigInt <= 0n) {
            alert('Token ID must be greater than 0');
            return;
        }

        const amountFloat = parseFloat(amountInput);
        if (isNaN(amountFloat) || amountFloat <= 0) {
            alert('Please enter a valid positive amount');
            return;
        }
        const amountWei = BigInt(Math.floor(amountFloat * 1e18));

        if (typeof window.ethereum === 'undefined') {
            alert('Please install a Web3 wallet (e.g., MetaMask) to request withdrawal');
            return;
        }

        partialButton.disabled = true;
        partialButton.textContent = 'Requesting...';

        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
        if (!accounts || accounts.length === 0) {
            throw new Error('No accounts found');
        }

        const userAddress = accounts[0];

        await window.ethereum.request({
            method: 'wallet_switchEthereumChain',
            params: [{ chainId: `0x${currentNetwork.chainId.toString(16)}` }]
        });

        const withdrawalCallData = iface.encodeFunctionData('requestPartialWithdrawal', [tokenIdBigInt, amountWei]);

        const transaction = {
            to: currentNetwork.mainAddress,
            data: withdrawalCallData,
            from: userAddress,
            value: '1000000000'
        };

        const txHash = await window.ethereum.request({
            method: 'eth_sendTransaction',
            params: [transaction]
        });

        alert(`Partial withdrawal request sent! Hash: ${txHash}\nFunds will be available after the request is processed.`);

        setTimeout(async () => {
            await updateTokenDisplay(tokenId);
            partialButton.disabled = false;
            partialButton.textContent = 'Request Partial Withdrawal';
        }, 5000);

    } catch (error) {
        console.error('Error requesting partial withdrawal:', error);
        alert(`Error requesting partial withdrawal: ${error.message}`);
        partialButton.disabled = false;
        partialButton.textContent = 'Request Partial Withdrawal';
    }
}

async function switchToCompounding() {
    const tokenId = document.getElementById('tokenInput').value.trim();
    const button = document.getElementById('switchToCompoundingButton');

    const iface = new ethers.Interface(ERCXXXXABI);

    if (!tokenId) {
        alert('Please enter a token ID first');
        return;
    }

    try {
        const tokenIdBigInt = BigInt(tokenId);
        if (tokenIdBigInt <= 0n) {
            alert('Token ID must be greater than 0');
            return;
        }

        if (typeof window.ethereum === 'undefined') {
            alert('Please install a Web3 wallet (e.g., MetaMask) to switch to compounding');
            return;
        }

        button.disabled = true;
        button.textContent = 'Switching...';

        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
        if (!accounts || accounts.length === 0) {
            throw new Error('No accounts found');
        }

        const userAddress = accounts[0];

        await window.ethereum.request({
            method: 'wallet_switchEthereumChain',
            params: [{ chainId: `0x${currentNetwork.chainId.toString(16)}` }]
        });

        const callData = iface.encodeFunctionData('requestSwitchToCompounding', [tokenIdBigInt]);

        const transaction = {
            to: currentNetwork.mainAddress,
            data: callData,
            from: userAddress,
            value: '1000000000'
        };

        const txHash = await window.ethereum.request({
            method: 'eth_sendTransaction',
            params: [transaction]
        });

        alert(`Switch to compounding request sent! Hash: ${txHash}\nThe change will take effect after the request is processed.`);

        setTimeout(async () => {
            await updateTokenDisplay(tokenId);
            button.disabled = false;
            button.textContent = 'Switch to Compounding';
        }, 5000);

    } catch (error) {
        console.error('Error switching to compounding:', error);
        alert(`Error switching to compounding: ${error.message}`);
        button.disabled = false;
        button.textContent = 'Switch to Compounding';
    }
}

function dismissDisclaimer() {
    const disclaimer = document.getElementById('disclaimer');
    if (disclaimer) {
        disclaimer.classList.add('hidden');
        localStorage.setItem('disclaimerDismissed', 'true');
    }
}

function initDisclaimer() {
    const disclaimer = document.getElementById('disclaimer');
    if (disclaimer && localStorage.getItem('disclaimerDismissed') === 'true') {
        disclaimer.classList.add('hidden');
    }
}

window.navigateToToken = navigateToToken;
window.pullExecutionLayerBalance = pullExecutionLayerBalance;
window.pullNative = pullNative;
window.requestFullWithdrawal = requestFullWithdrawal;
window.requestPartialWithdrawal = requestPartialWithdrawal;
window.switchToCompounding = switchToCompounding;
window.dismissDisclaimer = dismissDisclaimer;

document.addEventListener('DOMContentLoaded', () => {
    initDisclaimer();
    loadTokenFromURL();
});
