import type {Repository} from '@github-ui/current-repository'
import type {Model} from '@github-ui/marketplace-common'

export const MessageRoleValues = ['user', 'system', 'assistant', 'error', 'tool', 'developer'] as const
export type MessageRole = (typeof MessageRoleValues)[number]

// For now we're only supporting text content here
export type MessageContent = string

export type Message = {
  timestamp: Date
  message: MessageContent
  role: MessageRole
}

export type PromptAppPayload = {
  payload: {
    inferenceUrl: string
    restrictedModels: string[]
    prompt: string
    promptPath: string
    promptRef: string
    headPrompt?: string
    repository: Repository
    improvedSysPromptModel?: Model
  }
}

export type EvalsRow = {
  id: string
  [key: string]: string
}

export type Evals = {
  [evaluatorKey: string]: {
    score?: number
    pass?: boolean
  }
}

export type EvalsResult = {
  id: number
  completion: string
  evals: Evals
}
