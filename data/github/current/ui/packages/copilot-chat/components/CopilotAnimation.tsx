import {clsx} from 'clsx'
import {memo, useEffect, useMemo, useState} from 'react'

import type {CopilotChatMode} from '../utils/copilot-chat-types'
import CopilotAnimationActivate from './CopilotAnimationActivate'
import activateStyles from './CopilotAnimationActivate.module.css'
import affirmativeStyles from './CopilotAnimationAffirmative.module.css'
import CopilotAnimationAffirmativeSVG from './CopilotAnimationAffirmativeSVG'
import celebrateStyles from './CopilotAnimationCelebrate.module.css'
import CopilotAnimationCelebrateSVG from './CopilotAnimationCelebrateSVG'
import commonStyles from './CopilotAnimationCommon.module.css'
import confirmStyles from './CopilotAnimationConfirm.module.css'
import CopilotAnimationConfirmSVG from './CopilotAnimationConfirmSVG'
import idleStyles from './CopilotAnimationIdle.module.css'
import CopilotAnimationIdleSVG from './CopilotAnimationIdleSVG'
import jumpWiggleStyles from './CopilotAnimationJumpWiggle.module.css'
import CopilotAnimationJumpWiggleSVG from './CopilotAnimationJumpWiggleSVG'
import negativeStyles from './CopilotAnimationNegative.module.css'
import CopilotAnimationNegativeSVG from './CopilotAnimationNegativeSVG'
import CopilotAnimationStaticSVG from './CopilotAnimationStaticSVG'
import thinkingStyles from './CopilotAnimationThinking.module.css'
import CopilotAnimationThinkingSVG from './CopilotAnimationThinkingSVG'
import tickleStyles from './CopilotAnimationTickle.module.css'
import CopilotAnimationTickleSVG from './CopilotAnimationTickleSVG'
import userInputStyles from './CopilotAnimationUserInput.module.css'
import CopilotAnimationUserInputSVG from './CopilotAnimationUserInputSVG'

export const CopilotAnimationState = {
  Idle: 'idle',
  Starting: 'starting',
  Running: 'running',
  Ending: 'ending',
} as const

export type CopilotAnimationState = (typeof CopilotAnimationState)[keyof typeof CopilotAnimationState]

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
  animationType: CopilotAnimationType
  loopAnimation: boolean
  mode: CopilotChatMode
  onAnimationEnd?: () => void
}

const CopilotAnimation = ({animationType, onAnimationEnd, loopAnimation, mode}: CopilotAnimationProps) => {
  const [animationState, setAnimationState] = useState<CopilotAnimationState>(CopilotAnimationState.Idle)
  const [runningTime, setRunningTime] = useState<number>(0)

  const animationTime = animationTimes[animationType]
  useEffect(() => {
    setRunningTime(0)
    setAnimationState(CopilotAnimationState.Idle)
  }, [animationType])

  useEffect(() => {
    if (!animationTime || animationType === CopilotAnimationType.Static) return

    let timeoutId: NodeJS.Timeout
    if (animationState === CopilotAnimationState.Idle) {
      timeoutId = setTimeout(() => {
        setAnimationState(CopilotAnimationState.Starting)
      }, animationTime[CopilotAnimationState.Idle] || 0)
    }

    if (animationState === CopilotAnimationState.Starting) {
      timeoutId = setTimeout(() => {
        setAnimationState(CopilotAnimationState.Running)
        setRunningTime(Date.now())
      }, animationTime[CopilotAnimationState.Starting] || 0)
    }

    if (animationState === CopilotAnimationState.Running && !loopAnimation) {
      const elapsed = Date.now() - runningTime
      const runningAnimationDuration = animationTime[CopilotAnimationState.Running] || 0
      const remainingTime = runningAnimationDuration - (elapsed % runningAnimationDuration)
      timeoutId = setTimeout(() => {
        setAnimationState(CopilotAnimationState.Ending)
      }, remainingTime)
    }

    if (animationState === CopilotAnimationState.Ending) {
      timeoutId = setTimeout(() => {
        setAnimationState(CopilotAnimationState.Idle)
        setRunningTime(0)
        onAnimationEnd?.()
      }, animationTime[CopilotAnimationState.Ending] || 0)
    }

    return () => clearTimeout(timeoutId)

    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [animationState, loopAnimation, animationType])

  const copilotSVG = useMemo(() => {
    const stateToClassMap = {
      [CopilotAnimationState.Idle]: 'idleAnimation',
      [CopilotAnimationState.Starting]: 'startingAnimation',
      [CopilotAnimationState.Running]: 'runningAnimation',
      [CopilotAnimationState.Ending]: 'endingAnimation',
    }

    const stateToClass = (state: CopilotAnimationState, animationStyles: {[key: string]: string}) =>
      animationStyles[stateToClassMap[state]] || ''

    switch (animationType) {
      case CopilotAnimationType.Thinking:
        return <CopilotAnimationThinkingSVG stateClass={stateToClass(animationState, thinkingStyles)} />
      case CopilotAnimationType.Static:
        return <CopilotAnimationStaticSVG stateClass={stateToClass(animationState, commonStyles)} />
      case CopilotAnimationType.Affirmative:
        return <CopilotAnimationAffirmativeSVG stateClass={stateToClass(animationState, affirmativeStyles)} />
      case CopilotAnimationType.Celebrate:
        return (
          <CopilotAnimationCelebrateSVG
            stateClass={stateToClass(animationState, celebrateStyles)}
            ariaLabel="Copilot (Celebrate)"
          />
        )
      case CopilotAnimationType.Negative:
        return <CopilotAnimationNegativeSVG stateClass={stateToClass(animationState, negativeStyles)} />
      case CopilotAnimationType.Idle:
        return <CopilotAnimationIdleSVG stateClass={stateToClass(animationState, idleStyles)} />
      case CopilotAnimationType.Confirm:
        return <CopilotAnimationConfirmSVG stateClass={stateToClass(animationState, confirmStyles)} />
      case CopilotAnimationType.UserInput:
        return <CopilotAnimationUserInputSVG stateClass={stateToClass(animationState, userInputStyles)} />
      case CopilotAnimationType.Tickle:
        return <CopilotAnimationTickleSVG stateClass={stateToClass(animationState, tickleStyles)} />
      case CopilotAnimationType.JumpWiggle:
        return <CopilotAnimationJumpWiggleSVG stateClass={stateToClass(animationState, jumpWiggleStyles)} />
      case CopilotAnimationType.Activate:
        return <CopilotAnimationActivate stateClass={stateToClass(animationState, activateStyles)} />
    }
  }, [animationType, animationState])

  return (
    <div className={clsx(commonStyles.copilotAnimationHolder, mode === 'assistive' && commonStyles.assistive)}>
      <div className={commonStyles.copilotAnimation}>{copilotSVG}</div>
    </div>
  )
}

export default memo(CopilotAnimation)
