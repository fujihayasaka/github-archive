import type {Message} from '../api'
import type {DataRow} from '../config'

export type EvaluationResult = {
  pass?: boolean

  score?: number

  error?: string
}

export interface Evaluator {
  name: string

  evaluate(prompt: Message[], completion: Message, row: DataRow, s?: AbortSignal): Promise<EvaluationResult>
}
