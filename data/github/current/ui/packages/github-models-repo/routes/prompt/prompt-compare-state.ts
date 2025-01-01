import type {EvaluatorCfg} from './evals-sdk/config'
import type {EvaluationResult} from './evals-sdk/evaluator/evaluator'
import type {ResultRow} from './evals-sdk/result'
import type {PromptConfig} from './prompts'
import type {EvalsRow, Message} from './types'

export type PromptCompareState = {
  /** Current prompts. The first one is the active prompt for the prompt editor view */
  prompts: PromptConfig[]

  /** Current messages for the prompt view */
  messages: Message[]

  variables: Record<string, string>

  /** State for compare */
  compare: CompareState

  isDirty?: boolean

  error?: string
  isLoading: boolean
}

export type RowPromptResult = {
  completions: Message[]

  evals: EvaluationResult[]
}

export type CompareState = {
  isRunning: boolean

  rows: EvalsRow[]
  result: {
    // Index of RowPromptResult is the index in `prompts` of the shared state
    [rowId: number]: RowPromptResult[]
  }
  evaluators: EvaluatorState[]
}

export type EvaluatorState = {
  config: EvaluatorCfg

  // Some evaluators cannot be edited. If this was added from a built-in configuration, for example, it cannot be edited.
  readonly?: boolean
}

export type PromptCompareStateAction =
  | {type: 'ADD_PROMPT'; payload: {prompt: PromptConfig}}
  | {type: 'FORK_ORIGINAL_PROMPT'}
  | {type: 'REMOVE_PROMPT'; payload: {index: number}}
  | {type: 'UPDATE_PROMPT'; payload: {index?: number; prompt: PromptConfig}}
  | {type: 'SET_MESSAGES'; payload: {messages: Message[]}}
  | {type: 'SET_LOADING'; payload: {loading: boolean}}
  | {type: 'EVAL_ADD_ROW'; row: EvalsRow}
  | {type: 'EVAL_UPDATE_ROW'; row: EvalsRow}
  | {type: 'EVAL_REMOVE_ROW'; id: string}
  | {type: 'EVAL_CLEAR'}
  | {type: 'EVAL_ADD_EVALUATOR'; evaluator: EvaluatorState}
  | {type: 'EVAL_UPDATE_EVALUATOR'; payload: {index: number; evaluator: EvaluatorCfg}}
  | {type: 'EVAL_REMOVE_EVALUATOR'; index: number}
  | {type: 'EVAL_CLEAR_RESULT'}
  | {type: 'EVAL_UPDATE_RESULT_ROW'; row: ResultRow}
  | {type: 'EVAL_SET_IS_RUNNING'; payload: {isRunning: boolean}}
  | {type: 'EVAL_SET_ERROR'; payload: {error: string | undefined}}
  | {type: 'EVAL_SET_VARIABLES'; payload: {variables: Record<string, string>}}
