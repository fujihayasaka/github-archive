import {memo, useEffect, useState} from 'react'

import styles from './CopilotThinkingAnimation.module.css'
import CopilotThinkingAnimationSVG from './CopilotThinkingAnimationSVG'

enum CopilotAnimationState {
  Idle,
  Starting,
  Running,
  Ending,
}

const CopilotThinkingAnimation = ({isLoading}: {isLoading: boolean}) => {
  const [animation, setAnimation] = useState(CopilotAnimationState.Idle)
  const [runningTime, setRunningTime] = useState(0)

  // To keep in sync with the animation classes in the CSS file
  const startingAnimationDuration = 429
  const runningAnimationDuration = 1390
  const animationDelay = 1500

  useEffect(() => {
    let timeoutId: NodeJS.Timeout
    if (animation === CopilotAnimationState.Idle && isLoading) {
      timeoutId = setTimeout(() => {
        setAnimation(CopilotAnimationState.Starting)
      }, animationDelay)
    }

    if (animation === CopilotAnimationState.Starting) {
      timeoutId = setTimeout(() => {
        setAnimation(CopilotAnimationState.Running)
        setRunningTime(Date.now())
      }, startingAnimationDuration)
    }

    if (animation === CopilotAnimationState.Running && !isLoading) {
      const elapsed = Date.now() - runningTime
      const remainingTime = runningAnimationDuration - (elapsed % runningAnimationDuration)
      timeoutId = setTimeout(() => {
        setAnimation(CopilotAnimationState.Ending)
      }, remainingTime)
    }

    return () => clearTimeout(timeoutId)
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [animation, isLoading])

  return (
    <div className={styles.copilotAnimationHolder}>
      <div className={styles.copilotAnimation}>
        <CopilotThinkingAnimationSVG state={stateToClass(animation)} />
      </div>
    </div>
  )
}

function stateToClass(animation: CopilotAnimationState): string | undefined {
  switch (animation) {
    case CopilotAnimationState.Ending:
      return styles.endingAnimation
    case CopilotAnimationState.Starting:
      return styles.startingAnimation
    case CopilotAnimationState.Running:
      return styles.runningAnimation
    default:
      return styles.idleAnimation
  }
}

export default memo(CopilotThinkingAnimation)
