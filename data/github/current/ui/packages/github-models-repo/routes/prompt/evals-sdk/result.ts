import type {Message} from './api'
import type {DataRow, PromptCfg} from './config'
import type {EvaluationResult} from './evaluator/evaluator'

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
}

export type Result = ResultRow[]
