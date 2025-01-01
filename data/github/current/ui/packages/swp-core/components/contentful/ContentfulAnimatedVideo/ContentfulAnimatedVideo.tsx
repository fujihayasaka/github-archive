import {Box} from '@primer/react-brand'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {usePrefersReducedMotion} from '../../../lib/utils/videos'
import {PauseIcon, PlayIcon} from './ContentfulAnimatedVideoIcons'
import {getAnalyticsEvent} from '../../../lib/utils/analytics'
import styles from './ContentfulAnimatedVideo.module.css'
import type {AnimatedVideo} from '../../../schemas/contentful/contentTypes/animatedVideo'

export type AnimatedVideoProps = {
  component: AnimatedVideo
  analyticsLocation?: string
}

export function ContentfulAnimatedVideo({component, analyticsLocation}: AnimatedVideoProps) {
  const isReducedMotion = usePrefersReducedMotion()
  const {video, playLabel, pauseLabel, replayLabel} = component.fields

  const animatedVideoCopy = useMemo(
    () => ({
      label: {
        play: 'Play',
        pause: 'Pause',
        replay: 'Replay',
      },
      state: {
        playing: 'playing',
        paused: 'paused',
        ended: 'ended',
      },
      ariaLabel: {
        play: playLabel,
        pause: pauseLabel,
        replay: replayLabel,
      },
    }),
    [playLabel, pauseLabel, replayLabel],
  )

  const videoLgRef = useRef<HTMLVideoElement>(null)
  const [videoState, setVideoState] = useState(animatedVideoCopy.state.playing)
  const [videoButtonLabel, setVideoButtonLabel] = useState(animatedVideoCopy.label.pause)
  const [videoButtonPressed, setVideoButtonPressed] = useState(false)
  const [videoButtonAriaLabel, setVideoButtonAriaLabel] = useState(animatedVideoCopy.ariaLabel.pause)
  const [VideoIcon, setVideoIcon] = useState(() => PauseIcon)

  const setPausedButtonState = useCallback(() => {
    setVideoState(animatedVideoCopy.state.paused)
    setVideoButtonLabel(animatedVideoCopy.label.play)
    setVideoButtonPressed(true)
    setVideoButtonAriaLabel(animatedVideoCopy.ariaLabel.play)
    setVideoIcon(() => PlayIcon)
  }, [animatedVideoCopy])

  const setPlayingButtonState = useCallback(() => {
    setVideoState(animatedVideoCopy.state.playing)
    setVideoButtonLabel(animatedVideoCopy.label.pause)
    setVideoButtonAriaLabel(animatedVideoCopy.ariaLabel.pause)
    setVideoButtonPressed(false)
    setVideoIcon(() => PauseIcon)
  }, [animatedVideoCopy])

  const setReplayButtonState = () => {
    setVideoState(animatedVideoCopy.state.ended)
    setVideoButtonLabel(animatedVideoCopy.label.replay)
    setVideoButtonAriaLabel(animatedVideoCopy.ariaLabel.replay)
    setVideoButtonPressed(true)
    setVideoIcon(() => PlayIcon)
  }

  const introVideoPlay = () => {
    const playPromiseLg = videoLgRef.current?.play()
    // eslint-disable-next-line github/no-then
    if (playPromiseLg !== undefined) playPromiseLg.catch(() => {})
  }

  const introVideoPause = () => {
    videoLgRef.current?.pause()
  }

  const handleVideoStateChange = () => {
    if (!videoLgRef.current) return

    if (videoState === animatedVideoCopy.state.playing) {
      setPausedButtonState()
      introVideoPause()
      return
    }

    setPlayingButtonState()
    if (videoState === animatedVideoCopy.state.ended) {
      videoLgRef.current.currentTime = 0
    }

    introVideoPlay()
  }

  // On reduced motion change
  useEffect(() => {
    if (!videoLgRef.current) return

    if (isReducedMotion) {
      setPausedButtonState()
      introVideoPause()
      return
    }

    setPlayingButtonState()
    introVideoPlay()
  }, [isReducedMotion, setPausedButtonState, setPlayingButtonState])

  return (
    <Box className="position-relative width-full height-full">
      <Box role="img" className={styles.animatedVideoContainer} aria-label={video.fields?.description || ''}>
        <video
          playsInline
          muted
          className={styles.animatedVideoPlayer}
          ref={videoLgRef}
          onEnded={() => setReplayButtonState()}
        >
          <source src={video.fields.file.url} type="video/mp4; codecs=avc1.4d002a" />
        </video>
      </Box>

      <button
        className={styles.animatedVideoPlayerButton}
        onClick={handleVideoStateChange}
        aria-pressed={videoButtonPressed}
        aria-label={videoButtonAriaLabel}
        {...getAnalyticsEvent({
          action: videoButtonLabel.toLowerCase(),
          tag: 'button',
          context: video.fields?.description || '',
          location: analyticsLocation,
        })}
      >
        <VideoIcon className={styles.playButtonIcon} />
        <span className="sr-only">{videoButtonLabel}</span>
      </button>
    </Box>
  )
}
