/**
 * Decode base64 as a Uint8Array
 */
export function decode(encoded: string): Uint8Array {
  const bytes = atob(encoded)
    .split('')
    .map(x => x.charCodeAt(0))
  return Uint8Array.from(bytes)
}

/**
 * Encode a Uint8Array as base64
 */
export function encode(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
}
