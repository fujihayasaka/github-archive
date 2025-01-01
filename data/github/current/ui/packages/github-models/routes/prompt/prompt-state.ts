import type {MessagePair, ModelState, PlaygroundMessage, PlaygroundRequestParameters} from '../../types'

export type PromptState = {
  selectedLanguage: string
  selectedSDK: string

  model: ModelState

  promptFeedbackBannerDismissed?: boolean

  parameters?: PlaygroundRequestParameters
  variables: Record<string, string>
  systemPrompt: string | undefined
  prompt: string
  messagePairs?: MessagePair[]

  error?: string
}

export type PromptStateAction =
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
  | {type: 'SET_VARIABLES'; payload: {variables: Record<string, string>}}
