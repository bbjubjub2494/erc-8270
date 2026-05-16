export function formatAddress(address) {
    if (!address) return '';
    return `${address.substring(0, 6)}...${address.substring(address.length - 4)}`;
}

export function showError(statusMessage, message, timeout = 5000) {
    statusMessage.textContent = message;
    statusMessage.className = 'status-message error';
    statusMessage.style.display = 'block';
    setTimeout(() => {
        statusMessage.style.display = 'none';
    }, timeout);
}

export function showSuccess(statusMessage, message, timeout = 5000) {
    statusMessage.textContent = message;
    statusMessage.className = 'status-message success';
    statusMessage.style.display = 'block';
    setTimeout(() => {
        statusMessage.style.display = 'none';
    }, timeout);
}
