import {useCallback, useEffect, useRef, useState} from 'react'

const COUNTDOWN_DURATION = 5 // seconds
export const TRANSITION_DURATION = 0.4 // seconds
const CIRCLE_PATH_LENGTH = 590

export interface PlayButtonProps {
  playKey?: number
  onTimeout: () => void
  onPlayStateChange?: (state: boolean) => void
  duration?: number
  ariaLabel: {
    play: string
    pause: string
  }
  isDarkTheme?: boolean
  shouldAutoForward?: boolean
  hasLinkedTimelineEnded?: boolean
}

const defaultProps: Partial<PlayButtonProps> = {
  duration: COUNTDOWN_DURATION,
  isDarkTheme: false,
  shouldAutoForward: true,
  hasLinkedTimelineEnded: false,
}

const PlayIcon = () => (
  <svg width="20" height="20" viewBox="0 0 20 20" fill="none" role="presentation">
    <path
      d="M6.24905 3.69194C5.82218 3.45967 5.30225 3.76868 5.30225 4.25466V15.7452C5.30225 16.2312 5.82218 16.5402 6.24906 16.3079L16.8079 10.5626C17.2538 10.32 17.2538 9.67983 16.8079 9.4372L6.24905 3.69194ZM4.021 4.25466C4.021 2.79672 5.58078 1.86969 6.86142 2.56651L17.4203 8.31176C18.758 9.03966 18.758 10.9602 17.4203 11.6881L6.86143 17.4333C5.58079 18.1301 4.021 17.2031 4.021 15.7452V4.25466Z"
      fill="currentColor"
    />
  </svg>
)

const PauseIcon = () => (
  <svg width="20" height="20" viewBox="0 0 20 20" fill="none" role="presentation">
    <path
      d="M4.66148 2.3125C3.83593 2.3125 3.16669 2.98174 3.16669 3.80729V16.1927C3.16669 17.0183 3.83593 17.6875 4.66148 17.6875H7.65106C8.47662 17.6875 9.14586 17.0183 9.14586 16.1927V3.80729C9.14586 2.98174 8.47662 2.3125 7.65106 2.3125H4.66148ZM4.44794 3.80729C4.44794 3.68936 4.54355 3.59375 4.66148 3.59375H7.65106C7.769 3.59375 7.86461 3.68936 7.86461 3.80729V16.1927C7.86461 16.3106 7.769 16.4062 7.65106 16.4062H4.66148C4.54355 16.4062 4.44794 16.3106 4.44794 16.1927V3.80729ZM12.349 2.3125C11.5235 2.3125 10.8542 2.98174 10.8542 3.80729V16.1927C10.8542 17.0183 11.5235 17.6875 12.349 17.6875H15.3386C16.1642 17.6875 16.8334 17.0183 16.8334 16.1927V3.80729C16.8334 2.98174 16.1642 2.3125 15.3386 2.3125H12.349ZM12.1355 3.80729C12.1355 3.68936 12.2311 3.59375 12.349 3.59375H15.3386C15.4565 3.59375 15.5521 3.68936 15.5521 3.80729V16.1927C15.5521 16.3106 15.4565 16.4062 15.3386 16.4062H12.349C12.2311 16.4062 12.1355 16.3106 12.1355 16.1927V3.80729Z"
      fill="currentColor"
    />
  </svg>
)

const PlayButton: React.FC<PlayButtonProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {
    onTimeout,
    onPlayStateChange,
    ariaLabel,
    duration,
    playKey,
    isDarkTheme,
    shouldAutoForward,
    hasLinkedTimelineEnded,
  } = initializedProps

  const [isMounted, setIsMounted] = useState<boolean>(false)
  const [isPaused, setIsPaused] = useState<boolean>(false)
  const circleRef = useRef<SVGCircleElement>(null)
  const durationRef = useRef<number>(duration as number)
  const shouldTriggerAnimationOnResume = useRef<boolean>(false)
  const isRewinding = useRef<boolean>(false)

  const updatePauseState = useCallback(
    (state: boolean) => {
      setIsPaused(state)
      if (onPlayStateChange) onPlayStateChange(state)
    },
    [onPlayStateChange],
  )

  const onTogglePause = useCallback(() => {
    const newState = !isPaused
    updatePauseState(newState)
  }, [isPaused, updatePauseState])

  const animateCircle = useCallback(async () => {
    if (!shouldAutoForward) return

    if (circleRef.current) {
      for (const animation of circleRef.current.getAnimations()) {
        if (animation.playState !== 'idle') animation.cancel()
      }
    }

    if (isPaused) {
      shouldTriggerAnimationOnResume.current = true
      return
    }

    let forwardAnimation: Animation | undefined
    let rewindAnimation: Animation | undefined

    try {
      circleRef.current?.animate([{strokeOpacity: 0}, {strokeOpacity: 1}], {
        duration: (TRANSITION_DURATION / 2) * 1000,
        fill: 'forwards',
      })

      forwardAnimation = await circleRef.current?.animate(
        [{strokeDashoffset: CIRCLE_PATH_LENGTH}, {strokeDashoffset: 0}],
        {
          duration: durationRef.current * 1000,
          fill: 'forwards',
        },
      ).finished
    } catch {
      // Ignore
    }

    // Abort if the animation was cancelled
    if (!Number.isFinite(forwardAnimation?.startTime)) return
    onTimeout()

    isRewinding.current = true

    try {
      rewindAnimation = await circleRef.current?.animate([{strokeOpacity: 1}, {strokeOpacity: 0}], {
        duration: (TRANSITION_DURATION / 2) * 1000,
        fill: 'forwards',
      }).finished
    } catch {
      // Ignore
    }

    isRewinding.current = false

    // Abort if the animation was cancelled
    if (!Number.isFinite(rewindAnimation?.startTime)) return
    animateCircle()
  }, [isPaused, onTimeout, shouldAutoForward])

  useEffect(() => {
    if (!isPaused) {
      if (shouldTriggerAnimationOnResume.current) {
        shouldTriggerAnimationOnResume.current = false
        animateCircle()
      } else if (circleRef.current) {
        for (const animation of circleRef.current.getAnimations()) {
          animation.play()
        }
      }
    } else {
      if (circleRef.current) {
        for (const animation of circleRef.current.getAnimations()) {
          animation.pause()
        }
      }
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isPaused])

  useEffect(() => {
    durationRef.current = duration as number
  }, [duration])

  useEffect(() => {
    if (!isMounted) return

    if (!isRewinding.current) {
      if (shouldAutoForward) animateCircle()
      // If we're not auto-forwarding screens, we should unpause for the new screen
      // so its animation can be triggered
      else if (!shouldAutoForward && isPaused) updatePauseState(false)
    }
    // Use the autoPlayKey to force a reset if needed
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isMounted, duration, playKey])

  useEffect(() => {
    if (hasLinkedTimelineEnded) updatePauseState(true)
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hasLinkedTimelineEnded])

  useEffect(() => {
    setIsMounted(true)
  }, [])

  return (
    <button
      className={`PlayButton ${isDarkTheme ? 'PlayButton--dark' : ''}`}
      onClick={onTogglePause}
      aria-label={isPaused ? ariaLabel.play : ariaLabel.pause}
    >
      {shouldAutoForward && (
        <svg viewBox="0 0 200 200" role="presentation" className="PlayButton-timerBorder">
          <defs>
            <linearGradient id="gradientStroke" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stopColor="#b1b9c2" stopOpacity="1" />
              <stop offset="100%" stopColor="#ffffff" stopOpacity="0.7" />
            </linearGradient>
          </defs>

          <circle
            ref={circleRef}
            cx="50%"
            cy="50%"
            r="calc(50% - 6px)"
            fill="transparent"
            stroke="url(#gradientStroke)"
            strokeWidth="12"
            strokeLinecap="round"
            strokeDasharray={CIRCLE_PATH_LENGTH}
            strokeDashoffset={CIRCLE_PATH_LENGTH}
          />
        </svg>
      )}

      {isPaused ? <PlayIcon /> : <PauseIcon />}
    </button>
  )
}

export default PlayButton
