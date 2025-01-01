export const isBrowser = () => typeof window !== 'undefined'

export const isAndroid = () => {
  if (!isBrowser()) return false
  return /Android/i.test(window.navigator.userAgent)
}

export const isSafari = () => {
  if (!isBrowser()) return false
  const ua = window.navigator.userAgent
  return ua.includes('Safari') && !ua.includes('Chrome') && !ua.includes('Chromium')
}

export const checkPrefersReducedMotion = () => {
  let prefersReducedMotion = false
  if (!isBrowser()) return prefersReducedMotion

  if (window.matchMedia) {
    const motionMediaQuery = window.matchMedia('(prefers-reduced-motion)')
    prefersReducedMotion = motionMediaQuery.matches
  }

  return prefersReducedMotion
}

export const hasWebGLSupport = () => {
  if (!isBrowser()) return false
  const canvas = document.createElement('canvas')
  const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl')
  return gl && gl instanceof WebGLRenderingContext
}
