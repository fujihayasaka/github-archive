import type {TokenUsage} from '@github-ui/github-models'
import type {EvaluationResult, Message} from '../types'
import type {DataRow, PromptCfg} from './config'

export type ResultRow = {
  prompt: PromptCfg

  /**
   * Message are the messages sent to the model. They match the ones from the prompt config, with any variables
   * expanded and replaced
   */
  messages: Message[]

  /** Input row from dataset */
  data: DataRow

  completions: Message[]

  /** Evaluator results */
  evals: EvaluationResult[]

  tokenUsage: TokenUsage | undefined
}

export type Result = ResultRow[]
