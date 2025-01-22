// backend/security.js
const crypto = require('crypto');
const jwt = require('jsonwebtoken');

const API_KEYS_SALT = process.env.API_KEYS_SALT || 'default-salt';
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';

class SecurityManager {
    constructor() {
        this.apiKeys = new Map();
        this.keyRotationInterval = 24 * 60 * 60 * 1000; // 24 hours
        
        // Start key rotation
        setInterval(() => this.rotateKeys(), this.keyRotationInterval);
    }

    async verifyApiKey(apiKey) {
        try {
            // Verify format
            if (!this.isValidKeyFormat(apiKey)) {
                return false;
            }

            // Check if key exists and is not expired
            const keyInfo = this.apiKeys.get(apiKey);
            if (!keyInfo) {
                return false;
            }

            if (Date.now() > keyInfo.expiresAt) {
                this.apiKeys.delete(apiKey);
                return false;
            }

            // Verify hash
            const computedHash = this.computeKeyHash(apiKey, keyInfo.salt);
            return computedHash === keyInfo.hash;

        } catch (error) {
            console.error('Error verifying API key:', error);
            return false;
        }
    }

    generateSecurityHeaders(data) {
        const timestamp = Date.now().toString();
        const checksum = this.generateChecksum(data);
        const signature = this.signResponse(checksum, timestamp);

        return {
            'X-Timestamp': timestamp,
            'X-Checksum': checksum,
            'X-Signature': signature,
            'X-Security-Version': '1.0'
        };
    }

    generateApiKey(userId) {
        const key = crypto.randomBytes(32).toString('hex');
        const salt = crypto.randomBytes(16).toString('hex');
        const hash = this.computeKeyHash(key, salt);
        
        // Store key info
        this.apiKeys.set(key, {
            userId,
            hash,
            salt,
            createdAt: Date.now(),
            expiresAt: Date.now() + this.keyRotationInterval
        });

        return key;
    }

    // Private methods
    private computeKeyHash(key, salt) {
        return crypto
            .createHmac('sha256', API_KEYS_SALT)
            .update(key + salt)
            .digest('hex');
    }

    private isValidKeyFormat(key) {
        // Check key format (hex string of correct length)
        return /^[0-9a-f]{64}$/i.test(key);
    }

    private generateChecksum(data) {
        return crypto
            .createHash('sha256')
            .update(JSON.stringify(data))
            .digest('hex');
    }

    private signResponse(checksum, timestamp) {
        const dataToSign = `${checksum}:${timestamp}`;
        return jwt.sign(
            { data: dataToSign },
            JWT_SECRET,
            { expiresIn: '1h' }
        );
    }

    private rotateKeys() {
        const now = Date.now();
        for (const [key, info] of this.apiKeys.entries()) {
            if (now > info.expiresAt) {
                // Generate new key for user
                const newKey = this.generateApiKey(info.userId);
                
                // Remove old key
                this.apiKeys.delete(key);
                
                // Notify user of key rotation (implement notification system)
                this.notifyKeyRotation(info.userId, newKey);
            }
        }
    }

    private async notifyKeyRotation(userId, newKey) {
        // Implement notification system (email, webhook, etc.)
        console.log(`Key rotated for user ${userId}. New key: ${newKey}`);
    }
}

module.exports = new SecurityManager();
