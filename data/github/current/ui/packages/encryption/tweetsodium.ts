import {blake2bFinal, blake2bInit, blake2bUpdate} from 'blakejs'
import nacl from 'tweetnacl'

// Authenticated sealing only prepends the nonce to the ciphertext. Anonymous
// sealing also prepends a random public key.
const overheadLength = nacl.box.overheadLength + nacl.box.publicKeyLength

/**
 * Generates a 24 byte nonce that is a blake2b digest of the ephemeral
 * public key and the recipient's public key.
 *
 * @param epk - Ephemeral public key.
 * @param publicKey - Recipient's public key.
 *
 * @returns a 24-byte Uint8Array.
 */
export function sealNonce(epk: Uint8Array, publicKey: Uint8Array): Uint8Array {
  const hash = blake2bInit(nacl.box.nonceLength, false)

  blake2bUpdate(hash, epk)
  blake2bUpdate(hash, publicKey)
  return blake2bFinal(hash)
}

/**
 * Encrypt a message for a recipient.
 *
 * @param message - Message Uint8Array to encrypt.
 * @param publicKey - Recipient's public key Uint8Array.
 *
 * @returns an array whose length is 48 bytes greater than the message's.
 */
export function seal(message: Uint8Array, publicKey: Uint8Array): Uint8Array {
  const ekp = nacl.box.keyPair()

  const out = new Uint8Array(message.length + overheadLength)
  out.set(ekp.publicKey, 0)

  const nonce = sealNonce(ekp.publicKey, publicKey)

  const ct = nacl.box(message, nonce, publicKey, ekp.secretKey)
  out.set(ct, nacl.box.publicKeyLength)

  return out
}
