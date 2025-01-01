import type {WebCommitInfo} from '@github-ui/code-view-types'
import type {Repository} from '@github-ui/current-repository'
import type {TokenUsage} from '@github-ui/github-models'
import type {Model} from '@github-ui/marketplace-common'
import type {RefInfo} from '@github-ui/repos-types'

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
    commitInfo: {
      webCommitInfo: WebCommitInfo
      refInfo: RefInfo
      fileSaveAuthenticityToken: string
    }
    canEdit: boolean
    paidUsageBannerDismissed?: boolean
    businessSlug?: string
  }
}

export type PromptInfo = {
  ref: string
  sha: string
  path: string
  content: string
}

export type ReviewAppPayload = {
  payload: {
    inferenceUrl: string
    restrictedModels: string[]
    repository: Repository
    improvedSysPromptModel?: Model
    pull: {
      number: number
      title: string
    }
    basePrompt: PromptInfo
    headPrompt: PromptInfo
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

export type EvaluationResult = {
  pass?: boolean
  score?: number
  error?: string
}

export type RowPromptResult = {
  completions: Message[]
  evals: EvaluationResult[]
  tokenUsage?: TokenUsage
}

export type CompareRow = {
  id: number
  data: EvalsRow | null
  result?: RowPromptResult[]
}

export type DatasetTableItem = {id: number; data: EvalsRow | null; result?: RowPromptResult[]}

export type CompareMode = 'compare' | 'review'

// Analytics events
export const CompareForkPromptClicked = 'github_models.compare.fork_prompt.clicked'
export const CompareNewPromptClicked = 'github_models.compare.new_prompt.clicked'
export const AddEvaluatorSelectionClicked = 'github_models.compare.new_evaluator.clicked'
