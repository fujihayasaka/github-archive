import {useCallback, useEffect, useRef, useState, lazy, Suspense, useMemo} from 'react'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {Box} from '@primer/react-brand'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import {usePrefersReducedMotion} from '../../../../../lib/utils/platform'

import {PlayIcon, PauseIcon} from '../../extensions/components/CopilotIcons/CopilotIcons'

import ImageBgDesktop from '../../_assets/hero-bg-desktop.webp'
import ImageBgMobile from '../../_assets/hero-bg-mobile.webp'

const CopilotHeadWebGL = lazy(() => import('../../_components/CopilotHeadWebGL/CopilotHeadWebGL'))
const LegacyCopilotHeadWebGL = lazy(() => import('../../_components/LegacyCopilotHeadWebGL/LegacyCopilotHeadWebGL'))

type Props = {
  description?: string
  posterSrcLarge?: string
  posterSrcSmall?: string
  videoSrcLarge: string
  videoSrcSmall?: string
}

const heroVideoPlayerCopy = {
  label: {
    play: 'Play',
    pause: 'Pause',
    replay: 'Replay',
  },
  ariaLabel: {
    play: 'GitHub Copilot Chat demo video is currently paused. Click to play.',
    pause: 'GitHub Copilot Chat demo video is currently playing. Click to pause.',
    replay: 'GitHub Copilot Chat demo video has ended. Click to replay.',
  },
}

export function HeroVideo(props: Props) {
  const {description = '', posterSrcLarge, posterSrcSmall, videoSrcLarge, videoSrcSmall} = props

  const videoLgRef = useRef<HTMLVideoElement>(null)
  const videoSmRef = useRef<HTMLVideoElement>(null)
  const [videoState, setVideoState] = useState('playing')
  const [videoButtonLabel, setVideoButtonLabel] = useState(heroVideoPlayerCopy.label.pause)
  const [videoButtonPressed, setVideoButtonPressed] = useState(false)
  const [videoButtonAriaLabel, setVideoButtonAriaLabel] = useState(heroVideoPlayerCopy.ariaLabel.pause)
  const [VideoIcon, setVideoIcon] = useState(() => PauseIcon)

  const isReducedMotion = usePrefersReducedMotion()

  const isPostMsBuildLaunch = isFeatureEnabled('site_msbuild_launch')
  const isUsingMsBuildCopilotHead = isFeatureEnabled('site_msbuild_webgl_hero')

  const setPausedButtonState = useCallback(() => {
    setVideoState('paused')
    setVideoButtonLabel(heroVideoPlayerCopy.label.play)
    setVideoButtonPressed(true)
    setVideoButtonAriaLabel(heroVideoPlayerCopy.ariaLabel.play)
    setVideoIcon(() => PlayIcon)
  }, [])

  const setPlayingButtonState = useCallback(() => {
    setVideoState('playing')
    setVideoButtonLabel(heroVideoPlayerCopy.label.pause)
    setVideoButtonAriaLabel(heroVideoPlayerCopy.ariaLabel.pause)
    setVideoButtonPressed(false)
    setVideoIcon(() => PauseIcon)
  }, [])

  const setReplayButtonState = useCallback(() => {
    setVideoState('ended')
    setVideoButtonLabel(heroVideoPlayerCopy.label.replay)
    setVideoButtonAriaLabel(heroVideoPlayerCopy.ariaLabel.replay)
    setVideoButtonPressed(true)
    setVideoIcon(() => PlayIcon)
  }, [])

  const introVideoPlay = useCallback(() => {
    const playPromiseLg = videoLgRef.current?.play()
    // eslint-disable-next-line github/no-then
    if (playPromiseLg !== undefined) playPromiseLg.catch(() => {})

    const playPromiseSm = videoSmRef.current?.play()
    // eslint-disable-next-line github/no-then
    if (playPromiseSm !== undefined) playPromiseSm.catch(() => {})
  }, [])

  const introVideoPause = useCallback(() => {
    videoLgRef.current?.pause()
    videoSmRef.current?.pause()
  }, [])

  const handleVideoStateChange = useCallback(() => {
    if (!videoLgRef.current || !videoSmRef.current) return

    if (videoState === 'playing') {
      setPausedButtonState()
      introVideoPause()
      return
    }

    setPlayingButtonState()
    if (videoState === 'ended') {
      videoLgRef.current.currentTime = 0
      videoSmRef.current.currentTime = 0
    }

    introVideoPlay()
  }, [introVideoPause, introVideoPlay, setPausedButtonState, setPlayingButtonState, videoState])

  // On reduced motion change
  useEffect(() => {
    if (!videoLgRef.current || !videoSmRef.current) return

    if (isReducedMotion) {
      setPausedButtonState()
      introVideoPause()
      return
    }

    setPlayingButtonState()
    introVideoPlay()
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isReducedMotion, setPausedButtonState, setPlayingButtonState])

  const videosDOM = useMemo(
    () => (
      <>
        <video
          playsInline
          muted
          className="lp-Hero-video lp-Hero-video--landscape"
          width="1248"
          height="735"
          poster={posterSrcLarge}
          ref={videoLgRef}
          onEnded={() => setReplayButtonState()}
        >
          <source src={videoSrcLarge} type="video/mp4; codecs=avc1.4d002a" />
        </video>

        {videoSrcSmall ? (
          <video
            playsInline
            muted
            className="lp-Hero-video lp-Hero-video--portrait"
            width="539.5"
            height="682"
            ref={videoSmRef}
            poster={posterSrcSmall}
            onEnded={() => setReplayButtonState()}
          >
            <source src={videoSrcSmall} type="video/mp4; codecs=avc1.4d002a" />
          </video>
        ) : null}
      </>
    ),
    [posterSrcLarge, posterSrcSmall, setReplayButtonState, videoSrcLarge, videoSrcSmall],
  )

  return (
    <Box className="lp-Hero-visual">
      <Box role="img" className="lp-Hero-videoContainer" aria-label={description}>
        {isPostMsBuildLaunch && (
          <>
            <div className="lp-Hero-background">
              <img src={ImageBgDesktop} alt="" />
              <img src={ImageBgMobile} alt="" />
            </div>

            <div className="lp-Hero-glass">{videosDOM}</div>
          </>
        )}
        {!isPostMsBuildLaunch && videosDOM}
      </Box>

      <button
        className="lp-Hero-videoPlayerButton PlayButton PlayButton--gray"
        onClick={handleVideoStateChange}
        aria-pressed={videoButtonPressed}
        aria-label={videoButtonAriaLabel}
        {...getAnalyticsEvent({
          action: videoButtonLabel.toLowerCase(),
          tag: 'button',
          context: 'demo_gif',
          location: 'hero',
        })}
      >
        <VideoIcon />

        <span className="sr-only">{videoButtonLabel}</span>
      </button>

      <Suspense>
        {isPostMsBuildLaunch && isUsingMsBuildCopilotHead ? <CopilotHeadWebGL /> : <LegacyCopilotHeadWebGL />}
      </Suspense>
    </Box>
  )
}
