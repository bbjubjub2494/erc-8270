export function validateHexField(value, expectedLength, fieldName) {
    if (!value) {
        return { valid: false, error: `${fieldName} is missing` };
    }

    const cleanValue = value.startsWith('0x') ? value.slice(2) : value;

    if (!/^[0-9a-fA-F]+$/.test(cleanValue)) {
        return { valid: false, error: `${fieldName} contains invalid hex characters` };
    }

    if (cleanValue.length !== expectedLength) {
        return { valid: false, error: `${fieldName} has invalid length: ${cleanValue.length} (expected ${expectedLength})` };
    }

    return { valid: true, value: '0x' + cleanValue };
}

export function validateAddress(address) {
    if (!address) {
        return { valid: true, address: null };
    }

    const cleanAddress = address.startsWith('0x') ? address.slice(2) : address;

    if (!/^[0-9a-fA-F]+$/.test(cleanAddress)) {
        return { valid: false, error: 'Invalid hex characters in address' };
    }

    if (cleanAddress.length !== 40) {
        return { valid: false, error: `Invalid address length: ${cleanAddress.length} characters (expected 40)` };
    }

    return { valid: true, address: '0x' + cleanAddress };
}

export function validateValidatorKey(key) {
    const cleanKey = key.startsWith('0x') ? key.slice(2) : key;

    if (!/^[0-9a-fA-F]+$/.test(cleanKey)) {
        return { valid: false, error: 'Invalid hex characters' };
    }

    if (cleanKey.length !== 96) {
        return { valid: false, error: `Invalid length: ${cleanKey.length} characters (expected 96)` };
    }

    return { valid: true, key: '0x' + cleanKey };
}
