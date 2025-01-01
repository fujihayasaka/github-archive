import type {
  EvalsRow,
  EvalsState,
  EvaluatorState,
  MessagePair,
  ModelState,
  PlaygroundMessage,
  PlaygroundRequestParameters,
} from '../../types'
import type {EvaluatorCfg} from './evals-sdk/config'
import type {Result, ResultRow} from './evals-sdk/result'

export type PromptEvalsState = {
  selectedLanguage: string
  selectedSDK: string

  model: ModelState

  promptFeedbackBannerDismissed?: boolean

  parameters?: PlaygroundRequestParameters
  variables: Record<string, string>
  systemPrompt: string | undefined
  prompt: string
  messagePairs?: MessagePair[]

  evals: EvalsState

  error?: string
}

export type PromptEvalsStateAction =
  | {type: 'SET_IS_LOADING'; payload: {isLoading: boolean}}
  | {type: 'SET_PARAMETERS'; payload: {parameters: PlaygroundRequestParameters}}
  | {type: 'SET_PARAMETERS_HAS_CHANGES'; payload: {parametersHasChanges: boolean}}
  | {type: 'SET_SYSTEM_PROMPT'; payload: {systemPrompt: string}}
  | {type: 'SET_MODEL_STATE'; payload: {modelState: ModelState}}
  | {type: 'SET_MESSAGES'; payload: {messages: PlaygroundMessage[]}}
  | {type: 'SET_PROMPT_INPUT'; payload: {prompt: string}}
  | {type: 'SET_MESSAGE_PAIRS'; payload: {messagePairs: MessagePair[]}}
  | {type: 'SET_PROMPT_FEEDBACK_BANNER_DISMISSED'; payload: {dismissed: boolean}}
  | {type: 'CLEAR_PROMPTS_INPUT'}
  | {type: 'EVAL_ADD_ROW'; row: EvalsRow}
  | {type: 'EVAL_UPDATE_ROW'; row: EvalsRow}
  | {type: 'EVAL_REMOVE_ROW'; id: number}
  | {type: 'EVAL_CLEAR'}
  | {type: 'EVAL_ADD_EVALUATOR'; evaluator: EvaluatorState}
  | {type: 'EVAL_UPDATE_EVALUATOR'; payload: {index: number; evaluator: EvaluatorCfg}}
  | {type: 'EVAL_REMOVE_EVALUATOR'; index: number}
  | {type: 'EVAL_SET_RESULT'; result: Result}
  | {type: 'EVAL_UPDATE_RESULT_ROW'; row: ResultRow}
  | {type: 'EVAL_SET_IS_RUNNING'; payload: {isRunning: boolean}}
  | {type: 'EVAL_SET_ERROR'; payload: {error: string | undefined}}
  | {type: 'EVAL_SET_VARIABLES'; payload: {variables: Record<string, string>}}
