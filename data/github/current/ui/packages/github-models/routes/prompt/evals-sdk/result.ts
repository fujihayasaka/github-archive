import type {Message} from './api'
import type {ModelCfg} from './config'
import type {DataRow} from './dataset'
import type {EvaluationResult} from './evaluator/evaluator'

export type ResultRow = {
  model: ModelCfg

  /** Prompt is the prompt after expanding any variables */
  prompt: Message[]

  /** Input row from dataset */
  data: DataRow

  // TODO: Make this structured? Optionally?
  completion: string | null

  /** Evaluator results */
  evals: EvaluationResult[]
}

export type Result = ResultRow[]
