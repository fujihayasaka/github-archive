export interface CopilotAnimationStateProps {
  state: CopilotAnimationState
  scale?: number
}

export const CopilotAnimationState = {
  Idle: 'idle',
  Starting: 'starting',
  Running: 'running',
  Ending: 'ending',
} as const

export type CopilotAnimationState = (typeof CopilotAnimationState)[keyof typeof CopilotAnimationState]
