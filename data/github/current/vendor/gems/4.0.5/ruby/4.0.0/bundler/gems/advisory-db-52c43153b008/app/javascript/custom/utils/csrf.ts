// Get CSRF token from meta tag
export function getCsrfToken(): string {
  const metaTag = document.querySelector('meta[name="csrf-token"]')
  return metaTag ? metaTag.getAttribute('content') || '' : ''
}
