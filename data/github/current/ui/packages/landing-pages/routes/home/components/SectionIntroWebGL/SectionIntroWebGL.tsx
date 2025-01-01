import type {RefObject} from 'react'
import type React from 'react'
import {useEffect, useRef} from 'react'
import Artwork from './webgl/artwork'
import {hasWebGLSupport} from '../../../../lib/utils/platform'

import type {MascotType} from './mascot-type'
import type Assets from '../../webgl-utils/assets'

export interface SectionIntroWebGLProps {
  mascotName: MascotType['name']
  mascotRef: RefObject<HTMLDivElement>
  containerRef: RefObject<HTMLDivElement>
  startCopyAnimation: () => void
  isMascotOnly?: boolean
  assetsRef: React.RefObject<Assets>
}

const SectionIntroWebGL: React.FC<SectionIntroWebGLProps> = ({
  mascotName,
  mascotRef,
  containerRef,
  isMascotOnly,
  startCopyAnimation,
  assetsRef,
}) => {
  const webglRef = useRef<HTMLCanvasElement | null>(null)
  const wrapperRef = useRef<HTMLDivElement | null>(null)
  const animationFrameId = useRef(0)

  useEffect(() => {
    if (!hasWebGLSupport()) return startCopyAnimation()
    let artwork: Artwork | null = null
    let isInViewport = false
    let isClosed = false

    let isReducedMotion = false
    const handleReduceMotionChange = (event: MediaQueryListEvent) => {
      isReducedMotion = event.matches

      if (isReducedMotion) {
        if (artwork) {
          artwork.update({isReducedMotion: true})
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

    const resizeFunc = () => {
      if (mascotRef.current && containerRef.current && wrapperRef.current) {
        const mascotRectData = mascotRef.current.getBoundingClientRect()
        const containerRectData = containerRef.current.getBoundingClientRect()

        const webglTop = mascotRectData.top - containerRectData.top
        const webglWidth = mascotRectData.width
        const webglHeight = mascotRectData.height
        const margin = 10

        wrapperRef.current.style.height = `${webglHeight + margin * 2}px`
        wrapperRef.current.style.width = `${webglWidth + margin * 2}px`
        wrapperRef.current.style.top = `${webglTop - margin}px`
        wrapperRef.current.style.left = `${mascotRectData.left - containerRectData.left - margin}px`

        if (artwork) {
          artwork.resize()
        }
      }
    }

    if (wrapperRef.current && webglRef.current && mascotRef.current) {
      const assets = assetsRef.current
      if (!assets) return
      artwork = new Artwork(
        wrapperRef.current,
        webglRef.current,
        mascotRef.current,
        mascotName,
        isMascotOnly,
        isReducedMotion,
        assets,
      )
      artwork.setStartCopyAnimation(startCopyAnimation)
      assets.addCallback(() => {
        if (!isClosed) {
          if (artwork && isInViewport) {
            artwork.toggleVisibility(true, isReducedMotion)
          }

          if (isReducedMotion && artwork) {
            startCopyAnimation()
            artwork.update({isReducedMotion: true})
          }
        }
      })
    }

    resizeFunc()

    const scrollFunc = () => {
      if (artwork && isInViewport && !isReducedMotion) {
        artwork.scroll()
      }
    }

    // eslint-disable-next-line github/prefer-observers
    window.addEventListener('resize', resizeFunc)

    // eslint-disable-next-line github/prefer-observers
    window.addEventListener('scroll', scrollFunc)

    const tick = () => {
      if (!isReducedMotion) {
        if (artwork) {
          artwork.update({isReducedMotion: false})
        }
        animationFrameId.current = requestAnimationFrame(tick)
      }
    }

    const observer = new IntersectionObserver(
      entries => {
        for (const entry of entries) {
          const assets = assetsRef.current
          if (isReducedMotion) {
            if (entry.isIntersecting && artwork && assets?.isLoaded) {
              artwork.toggleVisibility(entry.isIntersecting, true)
              artwork.update({isReducedMotion: true})
            }
            return
          }
          if (entry.isIntersecting) {
            if (artwork && assets?.isLoaded) artwork.toggleVisibility(entry.isIntersecting, false)
            // Canvas is in the viewport, start rendering
            if (!animationFrameId.current) {
              tick()
            }
            isInViewport = true
          } else {
            // Canvas is out of the viewport, stop rendering
            if (animationFrameId.current) {
              cancelAnimationFrame(animationFrameId.current)
              animationFrameId.current = 0
            }

            isInViewport = false
          }
        }
      },
      {threshold: 0.1}, // Adjust the threshold as needed
    )

    if (webglRef.current) {
      observer.observe(webglRef.current)
    }

    return () => {
      if (animationFrameId.current) {
        cancelAnimationFrame(animationFrameId.current)
      }
      isClosed = true
      window.removeEventListener('resize', resizeFunc)
      window.removeEventListener('scroll', scrollFunc)
      mediaQuery.removeEventListener('change', handleReduceMotionChange)
      observer.disconnect()
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <div className="lp-SectionIntroWebGL" ref={wrapperRef as RefObject<HTMLDivElement>}>
      <canvas className="lp-SectionIntroWebGL-canvas" ref={webglRef as RefObject<HTMLCanvasElement>} />
    </div>
  )
}

export default SectionIntroWebGL
