import type React from 'react'
import {Fragment, useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {BreakpointSize, Link, Heading, Image, Text, useWindowSize} from '@primer/react-brand'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import PlayButton, {type PlayButtonProps} from '../PlayButton/PlayButton'
import useVideo from '../../hooks/useVideo'
import {checkPrefersReducedMotion, isSafari} from '../../../../lib/utils/platform'
import useIntersectionObserver from '../../../../lib/hooks/useIntersectionObserver'
import {BREAKPOINT_DESKTOP_MIN_HEIGHT} from '../../utils/responsive'
import Particles from '../../assets/hero/particles.png'

const ASPECT_RATIOS = {
  mobile: [43, 42],
  desktop: [16, 9],
  copilotUI: [1000, 1196],
  hasText: [588, 400],
} as const

const getHeightFromRatio = (width: number, ratio: keyof typeof ASPECT_RATIOS) => {
  const [ratioWidth, ratioHeight] = ASPECT_RATIOS[ratio]
  return (width / ratioWidth) * ratioHeight
}

const getAspectRatioCssVars = () => {
  const cssVars = Object.entries(ASPECT_RATIOS).reduce(
    (acc, [key, [ratioWidth, ratioHeight]]) => ({
      ...acc,
      [`--aspect-ratio-${key}`]: `${ratioWidth} / ${ratioHeight}`,
    }),
    {},
  )

  return cssVars
}

export interface SectionHeroProps {
  visuals: Array<{
    type: 'image' | 'video'
    url: {
      mobile?: string
      desktop: string
    }
    poster?: {
      mobile?: string
      desktop?: string
    }
    alt: string
  }>
  isCopilotUI?: boolean
  hasPlayButton?: boolean
  playButtonAriaLabel?: PlayButtonProps['ariaLabel']
  text?: {
    title: string
    description: string
    link: {
      url: string
      label: string
    }
  }
  analyticsId?: string
}

const defaultProps: Partial<SectionHeroProps> = {}

const SectionHero: React.FC<SectionHeroProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {visuals, text, isCopilotUI, hasPlayButton, playButtonAriaLabel, analyticsId} = initializedProps

  const [isMounted, setIsMounted] = useState<boolean>(false)
  const [isVisible, setIsVisible] = useState<boolean>(false)
  const [shouldReduceMotion, setShouldReduceMotion] = useState<boolean>(false)
  const [currentVisualIndex, setCurrentVisualIndex] = useState<number>(0)
  const [previousVisualIndex, setPreviousVisualIndex] = useState<number>(-1)
  const [isPaused, setIsPaused] = useState<boolean>(false)
  const [hasVideoEnded, setHasVideoEnded] = useState<boolean>(false)
  const wrapperRef = useRef<HTMLDivElement | null>(null)
  const videoRef = useRef<HTMLVideoElement | null>(null)
  const visualFrameRef = useRef<HTMLDivElement | null>(null)
  const currentVisualIndexRef = useRef<number>(currentVisualIndex)

  const windowSize = useWindowSize()

  const {
    addListeners: addVideoListeners,
    removeListeners: removeVideoListeners,
    onVideoTimeUpdate,
  } = useVideo({videoRef, isPaused})

  const isDesktopView = useMemo(
    () =>
      [BreakpointSize.MEDIUM, BreakpointSize.LARGE, BreakpointSize.XLARGE, BreakpointSize.XXLARGE].includes(
        windowSize.currentBreakpointSize!,
      ),
    [windowSize],
  )

  const isSmallHeight = useMemo(
    () => (windowSize?.height && windowSize.height < BREAKPOINT_DESKTOP_MIN_HEIGHT) || false,
    [windowSize],
  )

  const {isIntersecting} = useIntersectionObserver(
    wrapperRef,
    {threshold: {mobile: 0.33, desktop: 0.5}, isOnce: true},
    !isSmallHeight && isDesktopView,
  )

  const currentVisual = useMemo(() => visuals[currentVisualIndex], [currentVisualIndex, visuals])

  const onVisualTimeout = useCallback(async () => {
    const newIndex = (currentVisualIndexRef.current + 1) % visuals.length

    removeVideoListeners()

    setPreviousVisualIndex(currentVisualIndexRef.current)
    setCurrentVisualIndex(newIndex)
  }, [removeVideoListeners, visuals?.length])

  const onPlayStateChange = useCallback((shouldPause: boolean) => {
    if (!shouldPause) setHasVideoEnded(false)
    setIsPaused(shouldPause)
  }, [])

  const onVideoEnded = useCallback(async () => {
    setHasVideoEnded(true)
  }, [])

  const visualDOM = useMemo(() => {
    return visuals.map((visual, index) => {
      const src = visual.url[!visual.url.mobile || isDesktopView ? 'desktop' : 'mobile'] as string
      const poster = visual.poster?.[!visual.poster.mobile || isDesktopView ? 'desktop' : 'mobile'] as string
      const className = `lp-SectionHero-visual-media ${
        index === currentVisualIndex ? 'lp-SectionHero-visual-media--current' : ''
      } ${index === previousVisualIndex ? 'lp-SectionHero-visual-media--previous' : ''}`

      if (visual.type === 'video') {
        return (
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <Fragment key={`visual_${index}`}>
            <div className="sr-only">{visual.alt}</div>
            <video
              ref={videoRef}
              className={className}
              muted
              playsInline
              src={isMounted ? src : ''}
              poster={isMounted ? poster : ''}
              onTimeUpdate={onVideoTimeUpdate}
              onEnded={onVideoEnded}
            />
          </Fragment>
        )
      }

      // eslint-disable-next-line @eslint-react/no-array-index-key
      return <Image key={`visual_${index}`} className={className} src={src} alt={visual.alt} loading="lazy" />
    })
  }, [currentVisualIndex, isDesktopView, isMounted, onVideoEnded, onVideoTimeUpdate, previousVisualIndex, visuals])

  useEffect(() => {
    if (!shouldReduceMotion && currentVisual && isIntersecting) {
      addVideoListeners()
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentVisualIndex])

  useEffect(() => {
    if (!isMounted) return
    setShouldReduceMotion(checkPrefersReducedMotion())
  }, [isMounted])

  useEffect(() => {
    if (shouldReduceMotion) {
      // Pause immediately if the user prefers reduced motion
      onPlayStateChange(true)
      // Make the hero visible immediately if the user prefers reduced motion
      setIsVisible(true)
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shouldReduceMotion])

  useEffect(() => {
    currentVisualIndexRef.current = currentVisualIndex
  }, [currentVisualIndex])

  useEffect(() => {
    if (isIntersecting) setIsVisible(true)
  }, [isIntersecting])

  useEffect(() => {
    // Apply the aspect ratio to the media element
    // This is done in JS to work around Safari's buggy implementation of `aspect-ratio`
    // cf. https://stackoverflow.com/questions/74504318/safari-padded-container-doesnt-respect-aspect-ratio
    if (!isSafari() || !visualFrameRef.current) return

    const mediaContainer = visualFrameRef.current.firstElementChild as HTMLElement
    if (!mediaContainer) return

    let aspectRatio: keyof typeof ASPECT_RATIOS = 'mobile'
    if (isDesktopView) aspectRatio = 'desktop'
    if (isCopilotUI) aspectRatio = 'copilotUI'
    if (text) aspectRatio = 'hasText'

    const frameHeight = getHeightFromRatio(visualFrameRef.current.offsetWidth, aspectRatio)
    visualFrameRef.current.style.height = `${frameHeight}px`

    // Apply the right size to the media container, offseting the padding and border
    const {width, height} = visualFrameRef.current.getBoundingClientRect()
    const {
      paddingLeft,
      paddingRight,
      paddingTop,
      paddingBottom,
      borderLeftWidth,
      borderRightWidth,
      borderTopWidth,
      borderBottomWidth,
    } = window.getComputedStyle(visualFrameRef.current)

    const xPadding = parseFloat(paddingLeft) + parseFloat(paddingRight)
    const yPadding = parseFloat(paddingTop) + parseFloat(paddingBottom)
    const xBorder = parseFloat(borderLeftWidth) + parseFloat(borderRightWidth)
    const yBorder = parseFloat(borderTopWidth) + parseFloat(borderBottomWidth)

    mediaContainer.style.width = `${width - xPadding - xBorder}px`
    mediaContainer.style.height = `${height - yPadding - yBorder}px`

    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [windowSize])

  useEffect(() => {
    setIsMounted(true)

    return () => {
      removeVideoListeners()
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <div ref={wrapperRef} className="lp-SectionHero">
      <div className={`lp-SectionHero-glow ${text ? 'lp-SectionHero-glow--deeperBlue' : ''}`}>
        <div className="glow" />
        <img className="particles" src={Particles} alt="" aria-hidden="true" loading="lazy" />
      </div>
      <div className={`lp-SectionHero-background ${text ? 'lp-SectionHero-background--deeperBlue' : ''}`}>
        {!text && (
          <>
            <div className="glow" />
            <div className="glass" />
          </>
        )}
        {text && (
          <>
            <div className="glass" />
          </>
        )}
      </div>

      {hasPlayButton && playButtonAriaLabel && (
        <div className="lp-SectionHero-playButton">
          <PlayButton
            onTimeout={onVisualTimeout}
            onPlayStateChange={onPlayStateChange}
            ariaLabel={playButtonAriaLabel}
            shouldAutoForward={visuals.length > 1}
            hasLinkedTimelineEnded={hasVideoEnded}
          />
        </div>
      )}

      <div
        className={`lp-SectionHero-content ${text ? 'lp-SectionHero-content--hasText' : ''} ${
          !isVisible ? 'lp-SectionHero-content--hidden' : ''
        }`}
      >
        {text ? (
          <div className="lp-SectionHero-text">
            <Heading as="h3" size="6" weight="semibold" className="lp-SectionHero-text-title">
              {text.title}
              <span>{text.description}</span>
            </Heading>

            <div>
              <Link
                href={text.link.url}
                variant="accent"
                className="lp-SectionHero-text-link"
                {...getAnalyticsEvent({
                  action: text.link.label,
                  tag: 'link',
                  context: 'section_hero',
                  location: analyticsId,
                })}
              >
                <Text size="300">{text.link.label}</Text>
              </Link>
            </div>
          </div>
        ) : null}

        <div className="lp-SectionHero-visual">
          <div
            ref={visualFrameRef}
            className={`lp-SectionHero-visual-frame ${isCopilotUI ? 'lp-SectionHero-visual-frame--copilotUI' : ''}`}
            style={{...getAspectRatioCssVars()}}
          >
            <div>{visualDOM}</div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default SectionHero
