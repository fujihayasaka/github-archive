import nacl from 'tweetnacl'
import {sealNonce} from './tweetsodium'

export type KeyPair = {
  publicKey: Uint8Array
  secretKey: Uint8Array
}

export function newKeyPair(): KeyPair {
  return nacl.box.keyPair()
}

// eslint-disable-next-line no-barrel-files/no-barrel-files
export {sealNonce}

export function unseal(sealed: Uint8Array, rkp: KeyPair): Uint8Array | null {
  const epk = sealed.slice(0, nacl.box.publicKeyLength)
  const ciphertext = sealed.slice(nacl.box.publicKeyLength)
  const nonce = sealNonce(epk, rkp.publicKey)
  return nacl.box.open(ciphertext, nonce, epk, rkp.secretKey)
}
