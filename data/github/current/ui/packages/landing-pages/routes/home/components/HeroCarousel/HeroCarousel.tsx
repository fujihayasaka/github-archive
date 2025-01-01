import type React from 'react'
import {BreakpointSize, Image, useWindowSize} from '@primer/react-brand'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'

import PlayButton, {TRANSITION_DURATION, type PlayButtonProps} from '../PlayButton/PlayButton'
import {wait} from '../../utils/time'
import {SCREENS, HeroScreenId} from './HeroCarousel.data'
import useMotion from './HeroCarousel.motion'
import {checkPrefersReducedMotion} from '../../../../lib/utils/platform'
import useVideo from '../../hooks/useVideo'
import useIntersectionObserver from '../../../../lib/hooks/useIntersectionObserver'
import {BREAKPOINT_DESKTOP_MIN_HEIGHT} from '../../utils/responsive'

export interface HeroCarouselProps {
  currentScreenIndex: number
  onAutoPlayTimeout: (newScreenIndex: number) => void
  carouselAriaLabel?: string
  playButtonAriaLabel: PlayButtonProps['ariaLabel']
  isVisible?: boolean
}

const defaultProps: Partial<HeroCarouselProps> = {
  isVisible: true,
}

const screenSupportsDarkTheme = new Set<HeroScreenId>([
  HeroScreenId.collaborate,
  HeroScreenId.automate,
  HeroScreenId.secure,
])

const HeroCarousel: React.FC<HeroCarouselProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {currentScreenIndex, onAutoPlayTimeout, carouselAriaLabel, playButtonAriaLabel, isVisible} = initializedProps

  const [isMounted, setIsMounted] = useState<boolean>(false)
  const [shouldReduceMotion, setShouldReduceMotion] = useState<boolean>(false)
  const [isVisualVisible, setIsVisualVisible] = useState<boolean>(true)
  const [visibleScreenIndex, setVisibleScreenIndex] = useState<number>(currentScreenIndex)
  const [isPaused, setIsPaused] = useState<boolean>(false)
  const [hasTimelineEnded, setHasTimelineEnded] = useState<boolean>(false)
  const currentScreenIndexRef = useRef<number>(currentScreenIndex)
  const wrapperRef = useRef<HTMLDivElement | null>(null)
  const visualRef = useRef<HTMLDivElement | null>(null)
  const videoRef = useRef<HTMLVideoElement | null>(null)
  const windowSize = useWindowSize()

  const isDesktopView = useMemo(
    () =>
      [BreakpointSize.MEDIUM, BreakpointSize.LARGE, BreakpointSize.XLARGE, BreakpointSize.XXLARGE].includes(
        windowSize.currentBreakpointSize!,
      ),
    [windowSize],
  )
  const visibleScreen = useMemo(() => SCREENS[visibleScreenIndex], [visibleScreenIndex])
  const visibleScreenDuration = useMemo(
    () => visibleScreen?.visuals.reduce((previousValue, visual) => previousValue + visual.duration, 0) || 0,
    [visibleScreen],
  )

  const onTimelineEnded = useCallback(() => {
    setHasTimelineEnded(true)
  }, [])

  const {
    show: showTimeline,
    resume: resumeTimeline,
    pause: pauseTimeline,
    finish: finishTimeline,
  } = useMotion({visual: visualRef, onFinish: onTimelineEnded, isDesktopView})
  const {
    addListeners: addVideoListeners,
    removeListeners: removeVideoListeners,
    onVideoTimeUpdate,
  } = useVideo({videoRef, isPaused})

  const isSmallHeight = useMemo(
    () => (windowSize?.height && windowSize.height < BREAKPOINT_DESKTOP_MIN_HEIGHT) || false,
    [windowSize],
  )

  const {isIntersecting} = useIntersectionObserver(
    wrapperRef,
    {threshold: {mobile: 0.33, desktop: 0.5}, isOnce: true},
    !isSmallHeight && isDesktopView,
  )

  const onVisualTimeout = useCallback(() => {
    onAutoPlayTimeout((currentScreenIndexRef.current + 1) % SCREENS.length)
  }, [onAutoPlayTimeout])

  const onPlayStateChange = useCallback((shouldPause: boolean) => {
    setIsPaused(shouldPause)
    if (!shouldPause) setHasTimelineEnded(false)
  }, [])

  useEffect(() => {
    currentScreenIndexRef.current = currentScreenIndex

    if (!isVisible || !isIntersecting) return

    // Add delay to allow the transition to complete
    const proceed = async () => {
      if (shouldReduceMotion) {
        removeVideoListeners()
        setVisibleScreenIndex(currentScreenIndexRef.current)
        return
      }

      setIsVisualVisible(false)
      await wait((TRANSITION_DURATION / 2) * 1000)

      removeVideoListeners()

      setVisibleScreenIndex(currentScreenIndexRef.current)
      await wait((TRANSITION_DURATION / 2) * 1000)

      setIsVisualVisible(true)
    }

    proceed()
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentScreenIndex])

  useEffect(() => {
    if (!shouldReduceMotion && visibleScreen && isVisible && isIntersecting) {
      showTimeline(visibleScreen.id)
      addVideoListeners()
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visibleScreenIndex])

  useEffect(() => {
    if (!isMounted) return
    setShouldReduceMotion(checkPrefersReducedMotion())
  }, [isMounted])

  useEffect(() => {
    // Pause immediately if the user prefers reduced motion
    if (shouldReduceMotion) onPlayStateChange(true)
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shouldReduceMotion])

  useEffect(() => {
    if (!isIntersecting || !isVisible) return
    if (isPaused) pauseTimeline()
    else resumeTimeline()
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isPaused])

  useEffect(() => {
    if (!shouldReduceMotion && visibleScreen) {
      // Reposition elements when the window resizes
      finishTimeline(visibleScreen.id)
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [windowSize])

  useEffect(() => {
    setIsMounted(true)

    return () => {
      removeVideoListeners()
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <div ref={wrapperRef} className="lp-HeroCarousel">
      {carouselAriaLabel && <h2 className="visually-hidden">{carouselAriaLabel}</h2>}

      <div className="lp-HeroCarousel-background">
        <div />
        <div />
      </div>

      {!shouldReduceMotion && (
        <div className="lp-HeroCarousel-playButton">
          <PlayButton
            playKey={currentScreenIndex}
            duration={visibleScreenDuration}
            onTimeout={onVisualTimeout}
            onPlayStateChange={onPlayStateChange}
            ariaLabel={playButtonAriaLabel}
            shouldAutoForward={false}
            hasLinkedTimelineEnded={hasTimelineEnded}
            isDarkTheme={visibleScreen && isDesktopView && screenSupportsDarkTheme.has(visibleScreen.id)}
          />
        </div>
      )}

      <div className={`lp-HeroCarousel-container ${!isVisible ? 'lp-HeroCarousel-container--hidden' : ''}`}>
        <div className="lp-HeroCarousel-content">
          <div
            ref={visualRef}
            className={`lp-HeroCarousel-visual ${!isVisualVisible ? 'lp-HeroCarousel-visual--hidden' : ''}`}
          >
            {visibleScreen?.visuals.length
              ? visibleScreen.visuals.map((visual, index) => {
                  const key = `visual-${visibleScreen.id}-${index}`
                  const src = visual.url[!visual.url.mobile || isDesktopView ? 'desktop' : 'mobile'] as string
                  const poster = visual.poster?.[
                    !visual.poster.mobile || isDesktopView ? 'desktop' : 'mobile'
                  ] as string

                  return visual.type === 'video' ? (
                    <div key={key}>
                      <div className="sr-only">{visual.alt}</div>
                      <video
                        ref={videoRef}
                        muted
                        playsInline
                        src={isMounted ? src : ''}
                        poster={isMounted ? poster : ''}
                        onTimeUpdate={onVideoTimeUpdate}
                        onEnded={onTimelineEnded}
                        style={visual.zIndex ? {zIndex: visual.zIndex} : undefined}
                        className={visual.className}
                      />
                    </div>
                  ) : (
                    <Image
                      key={key}
                      src={src}
                      alt={visual.alt}
                      aria-hidden={visual.ariaHidden ? true : undefined}
                      style={visual.zIndex ? {zIndex: visual.zIndex} : undefined}
                      className={visual.className}
                    />
                  )
                })
              : null}

            {visibleScreen?.id === HeroScreenId.plan && (
              <div className="lp-HeroCarousel-visual-planMenu">
                <div />
                <div />
                <div />
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

export default HeroCarousel
