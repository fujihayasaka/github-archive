import {decode} from './utils'

/**
 * Encrypt a message for a recipient.
 *
 * @param publicKey - Recipient's public key Uint8Array, or base64 string.
 * @param message - Message to encrypt.
 */
export async function encrypt(publicKey: Uint8Array | string, value: string): Promise<Uint8Array> {
  const encoder = new TextEncoder()

  if (typeof publicKey === 'string') {
    publicKey = decode(publicKey)
  }

  const messageBytes = encoder.encode(value)
  const {seal} = await import('./tweetsodium')
  return seal(messageBytes, publicKey)
}
