import {useEffect, useRef, useState, useCallback, type VideoHTMLAttributes} from 'react'
import {PlayIcon, PauseIcon} from '../extensions/components/CopilotIcons/CopilotIcons'
import {usePrefersReducedMotion} from '../../../../lib/utils/platform'
import {analyticsEvent} from '../../../../lib/analytics'

interface VideoProps extends VideoHTMLAttributes<HTMLVideoElement> {
  src: string
  poster: string
  darkButton?: boolean
  analyticsProps?: {
    context: string
    location: string
  }
}

function useAutoplayVideo(ariaLabel = 'Video') {
  const videoRef = useRef<HTMLVideoElement | null>(null)
  const videoButtonRef = useRef<HTMLButtonElement | null>(null)
  const isReducedMotion = usePrefersReducedMotion()

  const heroVideoPlayerCopy = {
    label: {
      play: 'Play',
      pause: 'Pause',
      replay: 'Replay',
    },
    ariaLabel: {
      play: `${ariaLabel} is currently paused. Click to play.`,
      pause: `${ariaLabel} is currently playing. Click to pause.`,
      replay: `${ariaLabel} has ended. Click to replay.`,
    },
  }

  const [videoState, setVideoState] = useState('playing')
  const [videoButtonLabel, setVideoButtonLabel] = useState(heroVideoPlayerCopy.label.pause)
  const [videoButtonPressed, setVideoButtonPressed] = useState(false)
  const [videoButtonAriaLabel, setVideoButtonAriaLabel] = useState(heroVideoPlayerCopy.ariaLabel.pause)
  const [VideoIcon, setVideoIcon] = useState(() => PauseIcon)

  const setPausedButtonState = useCallback(() => {
    setVideoState('paused')
    setVideoButtonLabel(heroVideoPlayerCopy.label.play)
    setVideoButtonPressed(true)
    setVideoButtonAriaLabel(heroVideoPlayerCopy.ariaLabel.play)
    setVideoIcon(() => PlayIcon)
  }, [heroVideoPlayerCopy.ariaLabel.play, heroVideoPlayerCopy.label.play])

  const setPlayingButtonState = useCallback(() => {
    setVideoState('playing')
    setVideoButtonLabel(heroVideoPlayerCopy.label.pause)
    setVideoButtonAriaLabel(heroVideoPlayerCopy.ariaLabel.pause)
    setVideoButtonPressed(false)
    setVideoIcon(() => PauseIcon)
  }, [heroVideoPlayerCopy.ariaLabel.pause, heroVideoPlayerCopy.label.pause])

  const setReplayButtonState = () => {
    setVideoState('ended')
    setVideoButtonLabel(heroVideoPlayerCopy.label.replay)
    setVideoButtonAriaLabel(heroVideoPlayerCopy.ariaLabel.replay)
    setVideoButtonPressed(true)
    setVideoIcon(() => PlayIcon)
  }

  const introVideoPlay = () => {
    const playPromise = videoRef.current?.play()
    // eslint-disable-next-line github/no-then
    if (playPromise !== undefined) playPromise.catch(() => {})
  }

  const introVideoPause = () => {
    videoRef.current?.pause()
  }

  const handleVideoStateChange = () => {
    if (!videoRef.current) return

    if (videoState === 'playing') {
      setPausedButtonState()
      introVideoPause()
      return
    }

    setPlayingButtonState()
    if (videoState === 'ended') videoRef.current.currentTime = 0

    introVideoPlay()
  }

  useEffect(() => {
    if (!videoRef.current) return

    if (isReducedMotion) {
      setPausedButtonState()
      introVideoPause()
      return
    }

    setPlayingButtonState()
    introVideoPlay()
  }, [isReducedMotion, setPausedButtonState, setPlayingButtonState])

  useEffect(() => {
    const currentVideoRef = videoRef.current

    const observer = new IntersectionObserver(
      entries => {
        for (const entry of entries) {
          if (isReducedMotion) continue
          if (entry.isIntersecting) {
            if (currentVideoRef) {
              // eslint-disable-next-line github/no-then
              currentVideoRef.play().catch(() => {})
              observer.unobserve(currentVideoRef)
            }
          } else {
            if (currentVideoRef) currentVideoRef.pause()
          }
        }
      },
      {
        threshold: 0.5, // Play once 50% of the height is...
        rootMargin: `-25% 0% -25% 0%`, // ...in the center 50% of the viewport
      },
    )

    if (currentVideoRef) {
      observer.observe(currentVideoRef)
    }

    return () => {
      if (currentVideoRef) {
        observer.unobserve(currentVideoRef)
      }
    }
  }, [isReducedMotion])

  return {
    videoRef,
    videoButtonRef,
    videoState,
    videoButtonLabel,
    videoButtonPressed,
    videoButtonAriaLabel,
    VideoIcon,
    setReplayButtonState,
    setPlayingButtonState,
    setPausedButtonState,
    handleVideoStateChange,
  }
}

export default function AutoPlayVideo({src, poster, darkButton, analyticsProps, className, ...props}: VideoProps) {
  const refs = useAutoplayVideo(props['aria-label'])
  const VideoIcon = refs.VideoIcon
  const videoButtonLabel = refs.videoButtonLabel
  const videoButtonPressed = refs.videoButtonPressed
  const videoButtonAriaLabel = refs.videoButtonAriaLabel
  const handleVideoStateChange = refs.handleVideoStateChange
  const setReplayButtonState = refs.setReplayButtonState
  const setPlayingButtonState = refs.setPlayingButtonState
  const setPausedButtonState = refs.setPausedButtonState

  return (
    <div className={className} style={{position: 'relative'}}>
      <video
        ref={refs.videoRef}
        playsInline
        muted
        preload="none"
        poster={poster}
        className="d-block"
        {...props}
        onEnded={() => setReplayButtonState()}
        onPlay={() => setPlayingButtonState()}
        onPause={() => setPausedButtonState()}
      >
        <source src={src} type="video/mp4; codecs=avc1.4d002a" />
      </video>

      <button
        className={`PlayButton lp-PlayButton-video ${darkButton ? ' PlayButton--dark' : ''}`}
        onClick={handleVideoStateChange}
        aria-pressed={videoButtonPressed}
        aria-label={videoButtonAriaLabel}
        {...analyticsEvent({
          action: videoButtonLabel.toLowerCase(),
          tag: 'button',
          context: analyticsProps?.context || 'auto_play_video',
          location: analyticsProps?.location || '',
        })}
      >
        <VideoIcon />
        <span className="sr-only">{videoButtonLabel}</span>
      </button>
    </div>
  )
}
