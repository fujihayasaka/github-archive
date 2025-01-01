import {useEffect, useState} from 'react'

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

export const usePrefersReducedMotion = () => {
  const [prefersReducedMotion, setPrefersReducedMotion] = useState(false)

  useEffect(() => {
    if (!isBrowser()) return
    const mediaQuery = window.matchMedia('(prefers-reduced-motion)')
    setPrefersReducedMotion(mediaQuery.matches)

    const handleChange = () => {
      setPrefersReducedMotion(mediaQuery.matches)
    }

    mediaQuery.addEventListener('change', handleChange)

    return () => {
      mediaQuery.removeEventListener('change', handleChange)
    }
  }, [])

  return prefersReducedMotion
}

export const useDomReady = () => {
  const [isDomReady, setIsDomReady] = useState(false)

  useEffect(() => {
    if (isDomReady) return
    if (!isBrowser()) return

    const onDomReady = () => {
      setIsDomReady(true)
    }

    if (document.readyState === 'complete') {
      onDomReady()
    } else {
      window.addEventListener('load', onDomReady, {once: true})
    }

    return () => {
      window.removeEventListener('load', onDomReady)
    }
  }, [isDomReady])

  return isDomReady
}

export const hasWebGLSupport = () => {
  if (!isBrowser()) return false
  const canvas = document.createElement('canvas')
  const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl')
  return gl && gl instanceof WebGLRenderingContext
}
