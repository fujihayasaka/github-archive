export const isBrowser = () => typeof window !== 'undefined'

export const checkPrefersReducedMotion = () => {
  let prefersReducedMotion = false
  if (!isBrowser()) return prefersReducedMotion

  if (window.matchMedia) {
    const motionMediaQuery = window.matchMedia('(prefers-reduced-motion)')
    prefersReducedMotion = motionMediaQuery.matches
  }

  return prefersReducedMotion
}
