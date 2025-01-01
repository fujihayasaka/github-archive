import {clsx} from 'clsx'
import {memo, useEffect, useMemo, useRef, useState} from 'react'
import {useTrackingRef} from '@github-ui/use-tracking-ref'

import Activate from './states/Activate'
import Affirmative from './states/Affirmative'
import Celebrate from './states/Celebrate'
import Confirm from './states/Confirm'
import Idle from './states/Idle'
import JumpWiggle from './states/JumpWiggle'
import Negative from './states/Negative'
import Static from './states/Static'
import Thinking from './states/Thinking'
import Tickle from './states/Tickle'
import UserInput from './states/UserInput'
import {CopilotAnimationState} from './types'
import styles from './CopilotAnimation.module.css'
import {testIdProps} from '@github-ui/test-id-props'

export const CopilotAnimationType = {
  Affirmative: 'affirmative',
  Celebrate: 'celebrate',
  Tickle: 'tickle',
  JumpWiggle: 'jumpWiggle',
  Confirm: 'confirm',
  Idle: 'idle',
  Negative: 'negative',
  Static: 'static',
  Thinking: 'thinking',
  UserInput: 'userInput',
  Activate: 'activate',
} as const

export type CopilotAnimationType = (typeof CopilotAnimationType)[keyof typeof CopilotAnimationType]

type AnimationTime = {
  [key: string]: number
}

const animationTimes: Record<string, AnimationTime> = {
  [CopilotAnimationType.Thinking]: {
    [CopilotAnimationState.Idle]: 33,
    [CopilotAnimationState.Starting]: 429,
    [CopilotAnimationState.Running]: 1390,
    [CopilotAnimationState.Ending]: 429,
  },
  [CopilotAnimationType.Affirmative]: {
    [CopilotAnimationState.Idle]: 33,
    [CopilotAnimationState.Running]: 627,
  },
  [CopilotAnimationType.Celebrate]: {
    [CopilotAnimationState.Idle]: 33,
    [CopilotAnimationState.Running]: 1056,
  },
  [CopilotAnimationType.Negative]: {
    [CopilotAnimationState.Idle]: 250,
    [CopilotAnimationState.Running]: 792,
  },
  [CopilotAnimationType.Idle]: {
    [CopilotAnimationState.Running]: 13483,
  },
  [CopilotAnimationType.Confirm]: {
    [CopilotAnimationState.Idle]: 33,
    [CopilotAnimationState.Running]: 627,
  },
  [CopilotAnimationType.UserInput]: {
    [CopilotAnimationState.Idle]: 33,
    [CopilotAnimationState.Starting]: 363,
    [CopilotAnimationState.Running]: 3000,
    [CopilotAnimationState.Ending]: 528,
  },
  [CopilotAnimationType.Tickle]: {
    [CopilotAnimationState.Idle]: 33,
    [CopilotAnimationState.Running]: 1188,
  },
  [CopilotAnimationType.JumpWiggle]: {
    [CopilotAnimationState.Idle]: 33,
    [CopilotAnimationState.Running]: 1254,
  },
  [CopilotAnimationType.Activate]: {
    [CopilotAnimationState.Idle]: 33,
    [CopilotAnimationState.Running]: 2000,
  },
}

interface CopilotAnimationProps {
  /**
   * Select which animation to show. Note that this may not always update immediately - the component waits for any
   * running animation to finish before switching to the new one.
   */
  animationType: CopilotAnimationType
  /**
   * Control whether to loop the animation.
   * @default false
   */
  loopAnimation: boolean
  /**
   * Callback emitted when the animation ends. Is not called if `loopAnimation` is true.
   */
  onAnimationEnd?: () => void
  /**
   * The size of the animation. Cannot be smaller than 16.
   * Suggested sizes are 16, 24, 32, 48, 64, 96, 128.
   * @default 32
   */
  size?: number
  className?: string
  style?: React.CSSProperties
}

export const CopilotAnimation = memo(function CopilotAnimation({
  animationType,
  onAnimationEnd,
  loopAnimation,
  className,
  style,
  size = 32,
}: CopilotAnimationProps) {
  const [animationState, setAnimationState] = useState<CopilotAnimationState>(CopilotAnimationState.Idle)
  const startTime = useRef<number | null>(null)
  const computedSize = useMemo(() => (size >= 16 ? size : 16), [size])

  const scale = useMemo(() => (computedSize ? computedSize / 32 : 1), [computedSize])

  useEffect(() => {
    startTime.current = null
    setAnimationState(CopilotAnimationState.Idle)
  }, [animationType])

  const onAnimationEndRef = useTrackingRef(onAnimationEnd)

  useEffect(() => {
    const animationTime = animationTimes[animationType]

    if (!animationTime || animationType === CopilotAnimationType.Static) return

    let timeoutId: NodeJS.Timeout
    if (animationState === CopilotAnimationState.Idle && (loopAnimation || startTime.current === null)) {
      timeoutId = setTimeout(() => {
        setAnimationState(CopilotAnimationState.Starting)
      }, animationTime[CopilotAnimationState.Idle] || 0)
    }

    if (animationState === CopilotAnimationState.Starting) {
      timeoutId = setTimeout(() => {
        setAnimationState(CopilotAnimationState.Running)
        startTime.current = Date.now()
      }, animationTime[CopilotAnimationState.Starting] || 0)
    }

    if (animationState === CopilotAnimationState.Running && !loopAnimation) {
      const elapsed = startTime.current ? Date.now() - startTime.current : 0
      const runningAnimationDuration = animationTime[CopilotAnimationState.Running] || 0
      const remainingTime = runningAnimationDuration - (elapsed % runningAnimationDuration)
      timeoutId = setTimeout(() => {
        setAnimationState(CopilotAnimationState.Ending)
      }, remainingTime)
    }

    if (animationState === CopilotAnimationState.Ending) {
      timeoutId = setTimeout(() => {
        setAnimationState(CopilotAnimationState.Idle)
        if (!loopAnimation) onAnimationEndRef.current?.()
      }, animationTime[CopilotAnimationState.Ending] || 0)
    }

    return () => clearTimeout(timeoutId)
  }, [animationState, loopAnimation, animationType, onAnimationEndRef])

  const copilotSVG = useMemo(() => {
    switch (animationType) {
      case CopilotAnimationType.Thinking:
        return <Thinking state={animationState} scale={scale} />
      case CopilotAnimationType.Static:
        return <Static state={animationState} scale={scale} />
      case CopilotAnimationType.Affirmative:
        return <Affirmative state={animationState} scale={scale} />
      case CopilotAnimationType.Celebrate:
        return <Celebrate state={animationState} scale={scale} />
      case CopilotAnimationType.Negative:
        return <Negative state={animationState} scale={scale} />
      case CopilotAnimationType.Idle:
        return <Idle state={animationState} scale={scale} />
      case CopilotAnimationType.Confirm:
        return <Confirm state={animationState} scale={scale} />
      case CopilotAnimationType.UserInput:
        return <UserInput state={animationState} scale={scale} />
      case CopilotAnimationType.Tickle:
        return <Tickle state={animationState} scale={scale} />
      case CopilotAnimationType.JumpWiggle:
        return <JumpWiggle state={animationState} scale={scale} />
      case CopilotAnimationType.Activate:
        return <Activate state={animationState} scale={scale} />
    }
  }, [animationType, animationState, scale])

  return (
    <div
      className={clsx(
        className,
        styles.copilotAnimationHolder,
        animationType === CopilotAnimationType.Activate && styles.activate,
      )}
      {...testIdProps('copilot-animation')}
      style={{...style, '--copilot-animation-scale': scale}}
    >
      <div
        className={clsx(styles.copilotAnimation, animationType === CopilotAnimationType.Activate && styles.activate)}
      >
        {copilotSVG}
      </div>
    </div>
  )
})
