import {CopilotAnimation, CopilotAnimationType} from '@github-ui/copilot-animation'
import {Box} from '@primer/react'
import {clsx} from 'clsx'
import {memo, useEffect, useState} from 'react'

import type {CopilotChatMode} from '../utils/copilot-chat-types'
import styles from './CopilotBadgeV2.module.css'

/**
 * The state of the badge, which determines the animation to show.
 * @param animationType - the current animation running or to run
 * @param onFinish - the animation to switch to after the current animation finishes
 * @param loopAnimation - whether or not to loop the incoming animation
 */
type BadgeState = {
  animationType: CopilotAnimationType
  onFinish: CopilotAnimationType
  loopAnimation: boolean
  hasLoadedMessage: boolean
}

const INTERACTIVE_STATES: CopilotAnimationType[] = [
  CopilotAnimationType.Tickle,
  CopilotAnimationType.Celebrate,
  CopilotAnimationType.JumpWiggle,
]

const AFFIRM_KEYWORDS = [
  'yes',
  'absolutely',
  'certainly',
  'sure',
  'definitely',
  'right',
  'correct',
  'indeed',
  'precisely',
  'exactly',
  'true',
  'affirmative',
  'agree',
  'agreed',
]

const NEG_KEYWORDS = [
  'no',
  'never',
  'negative',
  'wrong',
  'false',
  'untrue',
  'cannot',
  "can't",
  'sorry',
  'incorrect',
  'deny',
  'disagree',
  'refuse',
  'unfortunately',
]

function isStrongAffirmative(message: string) {
  // Only check the first 200 characters of the message to reduce the chance of any
  // false positives from keywords that might appear in the middle of a long message.
  if (message.length < 200) {
    const tokens = message.toLowerCase().split(/\W+/).filter(Boolean)
    return AFFIRM_KEYWORDS.some(keyword => tokens.includes(keyword.toLowerCase()))
  }
  return false
}

function isStrongNegative(message: string) {
  if (message.length < 200) {
    const tokens = message.toLowerCase().split(/\W+/).filter(Boolean)
    return NEG_KEYWORDS.some(keyword => tokens.includes(keyword.toLowerCase()))
  }
  return false
}

interface GetNextAnimationState {
  previousState: BadgeState
  isLoadingSkills: boolean
  isAffirmativeSentiment: boolean
  isNegativeSentiment: boolean
  isError: boolean
  isLoading: boolean
}

function getNextAnimationState({
  previousState,
  isLoadingSkills,
  isAffirmativeSentiment,
  isNegativeSentiment,
  isError,
  isLoading,
}: GetNextAnimationState): BadgeState {
  switch (previousState.animationType) {
    case CopilotAnimationType.Static: {
      // Positive/negative sentiment
      if ((isAffirmativeSentiment || isNegativeSentiment) && !isError && !previousState.hasLoadedMessage) {
        return {
          animationType: isAffirmativeSentiment ? CopilotAnimationType.Affirmative : CopilotAnimationType.Negative,
          onFinish: CopilotAnimationType.Static,
          loopAnimation: false,
          hasLoadedMessage: true,
        }
      }

      // Thinking
      if (isLoadingSkills) {
        return {
          ...previousState,
          animationType: CopilotAnimationType.Thinking,
          loopAnimation: true,
        }
      }
      // Confirm (only if not loading, not error, not has loaded)
      if (!isLoading && !previousState.hasLoadedMessage && !isError) {
        return {
          animationType: CopilotAnimationType.Confirm,
          onFinish: CopilotAnimationType.Static,
          loopAnimation: false,
          hasLoadedMessage: true,
        }
      }
      // Error -> Negative
      if (isError && !previousState.hasLoadedMessage) {
        return {
          animationType: CopilotAnimationType.Negative,
          onFinish: CopilotAnimationType.Static,
          loopAnimation: false,
          hasLoadedMessage: true,
        }
      }
      return previousState
    }

    case CopilotAnimationType.Thinking: {
      // Once skills are done loading, either stay static or go negative if error
      if (!isLoadingSkills) {
        return {
          ...previousState,
          animationType: isError ? CopilotAnimationType.Negative : CopilotAnimationType.Static,
          loopAnimation: false,
        }
      }
      return previousState
    }

    default:
      return previousState
  }
}

function isRecentMessage(createdAt: string): boolean {
  const msgDateTime = new Date(createdAt)
  const now = new Date()
  const minsDiff = (now.getTime() - msgDateTime.getTime()) / 1000 / 60

  return minsDiff < 0.5
}

interface CopilotBadgeProps {
  isLoading?: boolean
  isError?: boolean
  className?: string
  isLoadingSkills?: boolean
  isFirstMessage?: boolean
  mode: CopilotChatMode
  message: string
  createdAt: string
}
/**
 * Originally only utilized in immersive chat, this Copilot avatar does not have a border and has a "loading dots"
 * animation to indicate when Copilot is thinking. Currently called "V2" since the original CopilotBadge is still
 * utilized in several places.
 */
export function CopilotBadge({
  isFirstMessage = false,
  isLoading,
  isLoadingSkills,
  isError,
  className,
  mode,
  message,
  createdAt,
}: CopilotBadgeProps) {
  const [badgeState, setBadgeState] = useState<BadgeState>(() => ({
    animationType:
      isFirstMessage && (!createdAt || isRecentMessage(createdAt))
        ? CopilotAnimationType.Celebrate
        : CopilotAnimationType.Static,
    onFinish: CopilotAnimationType.Static,
    loopAnimation: false,
    hasLoadedMessage: false,
  }))

  useEffect(() => {
    // Only update messages with a recent timestamp. This prevents
    // the badge from reanimating when conversations reload
    if (isRecentMessage(createdAt)) {
      setBadgeState(previousState =>
        getNextAnimationState({
          previousState,
          isLoadingSkills: isLoadingSkills || false,
          isError: isError || false,
          isLoading: isLoading || false,
          isAffirmativeSentiment: isStrongAffirmative(message),
          isNegativeSentiment: isStrongNegative(message),
        }),
      )
    }
  }, [
    isLoadingSkills,
    isError,
    isLoading,
    badgeState.animationType,
    badgeState.hasLoadedMessage,
    isFirstMessage,
    message,
    createdAt,
  ])

  const handleCelebrationClick = () => {
    if (!isLoading) {
      setBadgeState({
        ...badgeState,
        animationType: INTERACTIVE_STATES[Math.floor(Math.random() * INTERACTIVE_STATES.length)]!,
        onFinish: CopilotAnimationType.Static,
        loopAnimation: false,
      })
    }
  }
  return (
    <div
      className={clsx(styles.copilotBadge, isLoading && styles.loading, className)}
      aria-label="Copilot badge"
      role="img"
    >
      <Box sx={{':hover': {cursor: 'pointer'}}} onClick={handleCelebrationClick}>
        <CopilotAnimation
          animationType={badgeState.animationType}
          onAnimationEnd={() => setBadgeState(prev => ({...prev, animationType: prev.onFinish}))}
          loopAnimation={badgeState.loopAnimation}
          className={clsx(styles.animation, mode === 'assistive' && styles.assistive)}
        />
      </Box>
    </div>
  )
}

export default memo(CopilotBadge)
