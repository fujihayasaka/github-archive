import {ssrSafeDocument} from '@github-ui/ssr-utils'

export const FETCH_NONCE_HEADER = 'X-Fetch-Nonce'
export const FETCH_NONCE_TO_VALIDATE_HEADER = 'X-Fetch-Nonce-To-Validate'

export const fetchNonces = new Set<string>()

export function addValidNonce(newNonce: string) {
  fetchNonces.add(newNonce)
}

export function getFetchNonce() {
  return fetchNonces.values().next().value || ''
}

export function getFetchNonceHeaders(nonceToValidate?: string) {
  const headers: HeadersInit = {}

  // we still want to add the nonce to validate even if it is an empty string
  if (nonceToValidate !== undefined) {
    headers[FETCH_NONCE_TO_VALIDATE_HEADER] = nonceToValidate
  }

  if (nonceToValidate === undefined) {
    headers[FETCH_NONCE_HEADER] = getFetchNonce()
  } else if (fetchNonces.has(nonceToValidate)) {
    headers[FETCH_NONCE_HEADER] = nonceToValidate
  } else {
    headers[FETCH_NONCE_HEADER] = Array.from(fetchNonces).join(',')
  }

  return headers
}

export function setupInitialNonce() {
  const nonce = ssrSafeDocument?.head?.querySelector<HTMLMetaElement>('meta[name="fetch-nonce"]')?.content || ''
  if (nonce) {
    addValidNonce(nonce)
  }
}
