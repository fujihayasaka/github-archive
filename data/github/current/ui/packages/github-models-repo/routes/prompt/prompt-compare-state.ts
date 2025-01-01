import type {EvaluatorCfg} from './evals-sdk/config'
import type {ResultRow} from './evals-sdk/result'
import type {EvaluatorState, PromptCollection, PromptConfig} from './prompts'
import type {EvalsRow, Message, PromptInfo, RowPromptResult} from './types'

export type PromptCompareState = {
  /** Current prompts. The first one is the active prompt for the prompt editor view */
  prompts: PromptCollection

  /** Current messages for the prompt view */
  messages: Message[]

  variables: Record<string, string>

  /** State for compare */
  compare: CompareState

  /** State when reviewing changes */
  review?: ReviewState

  isDirty?: boolean

  error?: string
  isLoading: boolean
}

export type CompareState = {
  isRunning: boolean

  rows: EvalsRow[]
  skippedRowIds: Set<string>
  result: {
    // Index of RowPromptResult is the index in `prompts` of the shared state
    [rowId: number]: RowPromptResult[]
  }
  evaluators: EvaluatorState[]
}

export type ReviewState = {
  /** Matches the list of prompts in the compare prompt-compare state */
  promptInfo: PromptInfo[]
}

export type PromptCompareStateAction =
  | {type: 'ADD_PROMPT'; payload: {prompt: PromptConfig}}
  | {type: 'FORK_ORIGINAL_PROMPT'}
  | {type: 'REMOVE_PROMPT'; payload: {index: number}}
  | {type: 'UPDATE_PROMPT'; payload: {index?: number; prompt: PromptConfig}}
  | {type: 'UPDATE_PROMPT_PATH'; payload: {index?: number; path: string}}
  | {type: 'SET_MESSAGES'; payload: {messages: Message[]}}
  | {type: 'SET_LOADING'; payload: {loading: boolean}}
  | {type: 'EVAL_ADD_ROW'; row: EvalsRow}
  | {type: 'EVAL_UPDATE_ROW'; row: EvalsRow}
  | {type: 'EVAL_TOGGLE_ROW_SKIP'; id: string}
  | {type: 'EVAL_REMOVE_ROW'; id: string}
  | {type: 'EVAL_ADD_OR_UPDATE_ROW'; row: EvalsRow}
  | {type: 'EVAL_CLEAR'}
  | {type: 'EVAL_ADD_EVALUATOR'; evaluator: EvaluatorState}
  | {type: 'EVAL_UPDATE_EVALUATOR'; payload: {index: number; evaluator: EvaluatorCfg}}
  | {type: 'EVAL_REMOVE_EVALUATOR'; index: number}
  | {type: 'EVAL_CLEAR_RESULT'}
  | {type: 'EVAL_UPDATE_RESULT_ROW'; row: ResultRow}
  | {type: 'EVAL_SET_IS_RUNNING'; payload: {isRunning: boolean}}
  | {type: 'EVAL_SET_ERROR'; payload: {error: string | undefined}}
  | {type: 'EVAL_SET_VARIABLES'; payload: {variables: Record<string, string>}}
