import {CTABanner, Section} from '@primer/react-brand'

import {Spacer} from './_shared'
import CtaForm from './components/CtaForm/CtaForm'
import {useCallback, useEffect, useRef, useState} from 'react'
import useIntersectionObserver from '../../lib/hooks/useIntersectionObserver'
import {COPY} from './Cta.data'
import Artwork from './cta-webgl/artwork'
import Assets from './cta-webgl/assets'

export default function Cta() {
  const [isVisible, setIsVisible] = useState<boolean>(false)
  const mascotsRef = useRef<HTMLDivElement | null>(null)
  const ctaRef = useRef<HTMLDivElement | null>(null)
  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  const animationFrameId = useRef(0)

  // TODO: Replace the first once with the WebGL scene's intersection observer logic once added
  const {isIntersecting} = useIntersectionObserver(mascotsRef, {threshold: 0.4, isOnce: true})
  const {isIntersecting: isCtaInView} = useIntersectionObserver(ctaRef, {threshold: 0.4, isOnce: true})

  // TODO: To be called by WebGL scene once added
  const startCopyAnimation = useCallback(() => {
    setIsVisible(true)
  }, [])

  // TODO: To be removed once WebGL scene is added
  useEffect(() => {
    if (isIntersecting) {
      startCopyAnimation()
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isIntersecting])

  useEffect(() => {
    if (!isIntersecting) return
    let isReducedMotion = false
    let isInViewport = false
    let artwork: Artwork
    const assets: Assets = new Assets()
    const handleReduceMotionChange = (event: MediaQueryListEvent) => {
      isReducedMotion = event.matches

      if (isReducedMotion) {
        if (artwork) {
          if (isInViewport) {
            artwork.update(isReducedMotion)
          }
          if (animationFrameId.current) {
            cancelAnimationFrame(animationFrameId.current)
          }
        }
      } else {
        if (isInViewport) {
          tick()
        }
      }
    }

    const mediaQuery = window.matchMedia('(prefers-reduced-motion: reduce)')
    mediaQuery.addEventListener('change', handleReduceMotionChange)

    isReducedMotion = mediaQuery.matches

    const resize = () => {
      if (artwork) artwork.resize()
      if (isReducedMotion && artwork) artwork.update(isReducedMotion)
    }

    const scroll = () => {
      if (artwork) artwork.scroll(isReducedMotion)
    }

    const observer = new IntersectionObserver(
      entries => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            // Canvas is in the viewport, start rendering
            isInViewport = true
            if (isReducedMotion) {
              artwork.update(isReducedMotion)
            } else {
              tick()
            }
          } else {
            isInViewport = false
            if (animationFrameId.current) {
              cancelAnimationFrame(animationFrameId.current)
            }
          }
        }
      },
      {threshold: 0.1}, // Adjust the threshold as needed
    )

    if (mascotsRef.current && canvasRef.current) {
      artwork = new Artwork(mascotsRef.current, canvasRef.current, isReducedMotion, assets)
      observer.observe(canvasRef.current)
      assets.load(() => {
        artwork.afterLoad()
        resize()
        scroll()

        if (isReducedMotion) {
          artwork.update(isReducedMotion)
        }
      })
    }

    // eslint-disable-next-line github/prefer-observers
    window.addEventListener('resize', resize)
    // eslint-disable-next-line github/prefer-observers
    window.addEventListener('scroll', scroll)

    const tick = () => {
      if (isInViewport) {
        artwork.update(isReducedMotion)
        animationFrameId.current = requestAnimationFrame(tick)
      }
    }

    if (!isReducedMotion) {
      tick()
    }

    return () => {
      window.removeEventListener('resize', resize)
      window.removeEventListener('scroll', scroll)
      mediaQuery.removeEventListener('change', handleReduceMotionChange)
      observer.disconnect()
    }
  }, [isIntersecting])

  return (
    <Section id="cta">
      <Spacer size="100px" />
      <div ref={mascotsRef} className={`lp-Cta-mascots ${!isVisible ? 'lp-Cta-mascots--hidden' : ''}`}>
        <div className="sr-only">{COPY.visual.alt}</div>
        <canvas ref={canvasRef} />
      </div>

      <Spacer size="48px" size1012="80px" />

      <CTABanner
        ref={ctaRef}
        className={`lp-Cta ${isCtaInView ? 'is-visible' : ''}`}
        align="center"
        hasBackground={false}
        hasShadow={false}
      >
        <CTABanner.Heading as="h2">{COPY.heading}</CTABanner.Heading>
        <CTABanner.Description className="lp-Cta-description">{COPY.description}</CTABanner.Description>
        <CtaForm location="bottom_cta_section" />
      </CTABanner>
    </Section>
  )
}
