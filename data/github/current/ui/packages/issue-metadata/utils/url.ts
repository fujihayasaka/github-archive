import DOMPurify from 'dompurify'
import {dompurifyConfig} from './dompurifyConfig'

/**
 * Prefixes strings starting w/ www. w/ https:// protocols
 * This is to support link parsing in projects text fields because strings like www.google.com are treated
 * as valid urls, so we want to mirror the same functionality in issues project TextFields
 * @param url
 * @returns {string}
 */
export function prefixUrl(url: string) {
  const prefix = url?.startsWith('www.') ? 'https://' : ''
  return prefix + url
}

/**
 * A wrapper around URL.canParse that acts as a polyfill for older browsers
 * @param url
 * @returns {boolean} - True if the URL can be parsed, otherwise false.
 */
function canParse(url: string) {
  try {
    new window.URL(url)
    return true
  } catch {
    return false
  }
}

export const sanitizeInput = (input: string) => {
  return DOMPurify.sanitize(input, dompurifyConfig)
}

/**
 * Check whether a url is valid utilizing URL.canParse and uses a safe scheme (http or https)
 * @param url
 * @returns {boolean}
 */
export const isValidAndSafeUrl = (url: string) => {
  if (!url || !canParse(url)) return false

  try {
    const parsedUrl = new URL(url, window.location.origin)
    return ['http:', 'https:'].includes(parsedUrl.protocol)
  } catch {
    return false
  }
}

export const containsSafeContent = (url: string) => {
  return sanitizeInput(url) === url
}
