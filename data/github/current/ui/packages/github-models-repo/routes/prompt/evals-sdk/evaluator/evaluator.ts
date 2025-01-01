import type {Message, EvaluationResult} from '../../types'
import type {DataRow} from '../config'

export interface Evaluator {
  name: string

  evaluate(prompt: Message[], completion: Message, row: DataRow, s?: AbortSignal): Promise<EvaluationResult>
}
