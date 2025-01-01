import {useRef, useEffect} from 'react'
import Artwork from './intro-hero-webgl/artwork'
import Common from './intro-hero-webgl/common'
import type Assets from './webgl-utils/assets'
import {hasWebGLSupport} from '../../lib/utils/platform'

const COPY = {
  webgl: {
    alt: 'Mona the Octocat, Copilot, and Ducky float jubilantly upward from behind the GitHub product demo accompanied by a purple glow and a scattering of stars.',
  },
}

export default function IntroHero({
  setCopyScrollOpacity,
  setCopyScrollScale,
  assetsRef,
}: {
  setCopyScrollOpacity: (o: number) => void
  setCopyScrollScale: (o: number) => void
  assetsRef: React.RefObject<Assets>
}) {
  const wrapperRef = useRef<HTMLDivElement>(null)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const animationFrameId = useRef(0)

  useEffect(() => {
    if (!hasWebGLSupport()) return
    let isClosed = false
    let isReducedMotion = false

    const handleReduceMotionChange = (event: MediaQueryListEvent) => {
      isReducedMotion = event.matches

      if (isReducedMotion) {
        setCopyScrollScale(1)
        setCopyScrollOpacity(1)
        if (artwork) artwork.renderOnce()
      } else {
        tick()
      }
    }

    const mediaQuery = window.matchMedia('(prefers-reduced-motion: reduce)')
    mediaQuery.addEventListener('change', handleReduceMotionChange)
    isReducedMotion = mediaQuery.matches

    const common = new Common({isReduceMotion: isReducedMotion})
    const assets = assetsRef.current
    if (!assets) return
    const artwork = new Artwork(wrapperRef.current!, canvasRef.current!, common, assets)

    const resizeFunc = () => {
      artwork.resize()
      if (isReducedMotion || !artwork.isRendering) artwork.renderOnce()
    }
    // eslint-disable-next-line github/prefer-observers
    window.addEventListener('resize', resizeFunc)

    const scrollFunc = () => {
      artwork.scroll()
    }
    // eslint-disable-next-line github/prefer-observers
    window.addEventListener('scroll', scrollFunc)

    const callback = () => {
      if (isClosed) return
      artwork.init()
      if (isReducedMotion) artwork.renderOnce()
    }

    if (assets.isLoaded) {
      callback()
    } else {
      assets.addCallback(callback)
    }

    const tick = () => {
      if (isReducedMotion || !artwork) return

      artwork.update()

      if (common.isMobile) {
        setCopyScrollScale(1)
        setCopyScrollOpacity(1)
      } else {
        const scale = 1.0 - artwork.copyProgress.current * 0.1
        setCopyScrollScale(scale)

        const opacity = 1.0 - artwork.copyProgress.current
        setCopyScrollOpacity(opacity)

        const opacityCanvas = 1.0 - artwork.mascotProgress.current
        const scaleCanvas = 1.0 - artwork.mascotProgress.current * 0.1

        if (canvasRef.current) {
          canvasRef.current.style.opacity = `${opacityCanvas}`
          canvasRef.current.style.transform = `scale(${scaleCanvas})`
        }
      }

      animationFrameId.current = requestAnimationFrame(tick)
    }
    tick()

    const mouseEnterFunc = () => {
      if (!isReducedMotion && artwork) artwork.startCtaAnim()
    }

    const mouseLeaveFunc = () => {
      if (!isReducedMotion && artwork) artwork.stopCtaAnim()
    }

    const CtaActionRefs = document.querySelectorAll('.js-hero-action')
    for (const ctaActionRef of CtaActionRefs) {
      ctaActionRef.addEventListener('mouseenter', mouseEnterFunc)
      ctaActionRef.addEventListener('mouseleave', mouseLeaveFunc)
    }

    const handleBeforeUnload = () => {
      cancelAnimationFrame(animationFrameId.current)
    }
    window.addEventListener('beforeunload', handleBeforeUnload)

    return () => {
      for (const ctaActionRef of CtaActionRefs) {
        ctaActionRef.removeEventListener('mouseenter', mouseEnterFunc)
        ctaActionRef.removeEventListener('mouseleave', mouseLeaveFunc)
      }

      if (animationFrameId.current) {
        cancelAnimationFrame(animationFrameId.current)
      }
      isClosed = true
      window.removeEventListener('resize', resizeFunc)
      window.removeEventListener('scroll', scrollFunc)
      window.removeEventListener('beforeunload', handleBeforeUnload)
      mediaQuery.removeEventListener('change', handleReduceMotionChange)
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <div className="lp-IntroVisuals">
      <div className="lp-IntroVisuals-canvasWrapper" ref={wrapperRef}>
        <canvas className="lp-IntroVisuals-canvas" ref={canvasRef} />
      </div>
      <div className="sr-only">{COPY.webgl.alt}</div>
    </div>
  )
}
