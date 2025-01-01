import {
  CompletionTokensLimitReachedResponseError,
  o1ModelNames,
  type ModelClientSendMessageResponse,
  type TokenUsage,
  type TokenUsageInfo,
} from '@github-ui/github-models'
import type {AzureModelClient} from '@github-ui/github-models/AzureModelClient'
import {getDefaultTokenUsage} from '@github-ui/github-models/ModelUsage'
import {createContext, useContext, type Dispatch} from 'react'
import type {RepoModel, MessagePair, ResponseFormat} from '../../types'
import {buildEvalsConfig} from './evals-config'
import {runEval} from './evals-sdk'
import type {Config, DataRow, EvaluatorCfg} from './evals-sdk/config'
import {findModel} from './models'
import type {PromptCompareState, PromptCompareStateAction} from './prompt-compare-state'
import type {EvaluatorState, PromptConfig} from './prompts'
import type {EvalsRow, Message} from './types'
import {createAssistantMessage, createErrorMessage, createUserMessage} from './utils/message-utils'

export const PromptCompareManagerContext = createContext<PromptCompareManager>({} as PromptCompareManager)

export function usePromptCompareManager() {
  return useContext(PromptCompareManagerContext)
}

export function promptCompareReducer(state: PromptCompareState, action: PromptCompareStateAction): PromptCompareState {
  switch (action.type) {
    case 'SET_MESSAGES':
      return {...state, messages: action.payload.messages}

    case 'SET_LOADING':
      return {...state, isLoading: action.payload.loading}

    case 'ADD_PROMPT': {
      return {...state, prompts: [...state.prompts, action.payload.prompt]}
    }

    case 'FORK_ORIGINAL_PROMPT': {
      const originalPrompt = state.prompts[0]
      if (!originalPrompt) {
        throw new Error('No original prompt found to fork')
      }

      return {
        ...state,
        prompts: [...state.prompts, {...originalPrompt}],
      }
    }

    case 'REMOVE_PROMPT': {
      return {...state, prompts: state.prompts.filter((_, i) => i !== action.payload.index)}
    }

    case 'UPDATE_PROMPT': {
      const idx = action.payload.index || 0

      return {
        ...state,
        isDirty: true, // For now always mark as dirty whenever a prompt is updated.
        prompts: [...state.prompts.slice(0, idx), action.payload.prompt, ...state.prompts.slice(idx + 1)],
      }
    }

    case 'UPDATE_PROMPT_PATH': {
      const {path, index} = action.payload
      const idx = index || 0
      const updatedPrompt = {
        ...state.prompts[idx],
        path,
        messages: state.prompts[idx]?.messages ?? [], // Ensure messages is always defined
      }
      return {
        ...state,
        isDirty: true, // For now always mark as dirty whenever path is update
        prompts: [...state.prompts.slice(0, idx), updatedPrompt, ...state.prompts.slice(idx + 1)],
      }
    }

    case 'EVAL_ADD_ROW': {
      return {
        ...state,
        isDirty: true, // For now always mark as dirty whenever an eval row is updated.
        compare: {
          ...state.compare,
          rows: [...state.compare.rows, {...action.row, id: state.compare.rows.length.toString()} as EvalsRow],
        },
      }
    }
    case 'EVAL_UPDATE_ROW': {
      return {
        ...state,
        isDirty: true, // For now always mark as dirty whenever an eval row is updated.
        compare: {
          ...state.compare,
          rows: state.compare.rows.map(row => (row.id === action.row.id ? action.row : row)),
        },
      }
    }
    case 'EVAL_REMOVE_ROW': {
      return {
        ...state,
        isDirty: true, // For now always mark as dirty whenever an eval row is updated.
        compare: {
          ...state.compare,
          rows: state.compare.rows.filter(row => row.id !== action.id),
        },
      }
    }
    case 'EVAL_ADD_OR_UPDATE_ROW': {
      const row = state.compare.rows.find(r => r.id === action.row.id)

      if (row) {
        return {
          ...state,
          isDirty: true, // For now always mark as dirty whenever an eval row is updated.
          compare: {
            ...state.compare,
            rows: state.compare.rows.map(r => (r.id === action.row.id ? action.row : r)),
          },
        }
      } else {
        return {
          ...state,
          isDirty: true, // For now always mark as dirty whenever an eval row is updated.
          compare: {
            ...state.compare,
            rows: [...state.compare.rows, {...action.row, id: state.compare.rows.length.toString()}],
          },
        }
      }
    }
    case 'EVAL_TOGGLE_ROW_SKIP': {
      const wasSkipped = state.compare.skippedRowIds.has(action.id)
      return {
        ...state,
        compare: {
          ...state.compare,
          skippedRowIds: wasSkipped
            ? new Set([...state.compare.skippedRowIds].filter(id => id !== action.id))
            : new Set([...state.compare.skippedRowIds, action.id]),
        },
      }
    }

    case 'EVAL_CLEAR': {
      return {
        ...state,
        prompts: state.prompts.slice(0, 1),
        compare: {rows: [], skippedRowIds: new Set<string>(), result: [], evaluators: [], isRunning: false},
      }
    }

    case 'EVAL_ADD_EVALUATOR': {
      return {
        ...state,
        isDirty: true, // For now always mark as dirty whenever an evaluator is updated.
        compare: {...state.compare, evaluators: [...state.compare.evaluators, action.evaluator]},
      }
    }

    case 'EVAL_UPDATE_EVALUATOR': {
      return {
        ...state,
        isDirty: true,
        compare: {
          ...state.compare,
          evaluators: state.compare.evaluators.map((evaluator, i) =>
            i === action.payload.index
              ? {
                  ...evaluator,
                  config: action.payload.evaluator,
                }
              : evaluator,
          ),
        },
      }
    }

    case 'EVAL_REMOVE_EVALUATOR': {
      return {
        ...state,
        isDirty: true,
        compare: {
          ...state.compare,
          evaluators: state.compare.evaluators.filter((_, i) => i !== action.index),
          result: {}, // For now, reset the result when an evaluator is removed
        },
      }
    }

    case 'EVAL_SET_IS_RUNNING':
      return {
        ...state,
        compare: {
          ...state.compare,
          isRunning: action.payload.isRunning,
        },
      }

    case 'EVAL_CLEAR_RESULT': {
      const newResult = []
      for (let i = 0; i < state.compare.rows.length; i++) {
        const row = state.compare.rows[i]!
        if (state.compare.skippedRowIds.has(row.id)) {
          const prevRowResult = state.compare.result[i]
          if (prevRowResult) {
            newResult[i] = prevRowResult
          }
        }
      }
      return {...state, compare: {...state.compare, result: newResult}}
    }

    case 'EVAL_UPDATE_RESULT_ROW': {
      const resultRow = action.row

      const inputRowIdx = state.compare.rows.findIndex(x => x.id === resultRow.data.id)
      if (inputRowIdx === -1) {
        throw new Error('Cannot find result row, this should not happen')
      }

      // We're using the prompt index as the prompt id for now
      const promptIdx = resultRow.prompt.id
      if (promptIdx === undefined) {
        throw new Error('Cannot find prompt index, this should not happen')
      }

      return {
        ...state,
        compare: {
          ...state.compare,
          result: {
            ...state.compare.result,
            [inputRowIdx]: [
              ...(state.compare.result[inputRowIdx] || []).slice(0, promptIdx),
              resultRow,
              ...(state.compare.result[inputRowIdx] || []).slice(promptIdx + 1),
            ],
          },
        },
      }
    }

    case 'EVAL_SET_VARIABLES':
      return {
        ...state,
        variables: action.payload.variables,
      }

    case 'EVAL_SET_ERROR':
      return {
        ...state,
        error: action.payload.error,
      }

    default:
      return state
  }
}

export class PromptCompareManager {
  dispatch: Dispatch<PromptCompareStateAction>

  private evalsRunAbortController: AbortController | null = null

  constructor(dispatch: Dispatch<PromptCompareStateAction>) {
    this.dispatch = dispatch
  }

  updatePrompt(prompt: PromptConfig, index?: number) {
    this.dispatch({type: 'UPDATE_PROMPT', payload: {prompt, index}})
  }

  updatePromptPath(path: string, index?: number) {
    this.dispatch({type: 'UPDATE_PROMPT_PATH', payload: {path, index}})
  }

  addPrompt(prompt: PromptConfig) {
    this.dispatch({type: 'ADD_PROMPT', payload: {prompt}})
  }

  forkPrompt() {
    this.dispatch({type: 'FORK_ORIGINAL_PROMPT'})
  }

  removePrompt(index: number) {
    this.dispatch({type: 'REMOVE_PROMPT', payload: {index}})
  }

  setMessages(messages: Message[]) {
    this.dispatch({type: 'SET_MESSAGES', payload: {messages}})
  }

  resetHistory(setTokenUsage?: (tokenUsage: TokenUsage) => void) {
    this.setMessages([])
    setTokenUsage?.(getDefaultTokenUsage())
    this.setError(undefined)
  }

  setError(error: string | undefined) {
    this.dispatch({type: 'EVAL_SET_ERROR', payload: {error}})
  }

  setIsLoading(isLoading: boolean) {
    this.dispatch({type: 'SET_LOADING', payload: {loading: isLoading}})
  }

  setVariables(variables: Record<string, string>) {
    this.dispatch({type: 'EVAL_SET_VARIABLES', payload: {variables}})
  }

  async startEvalsRun(
    modelClient: AzureModelClient,
    models: RepoModel[],
    prompts: PromptConfig[],
    rows: DataRow[],
    evaluators: EvaluatorCfg[],
    promptResponseFormat: ResponseFormat = 'text',
    promptJsonSchema?: string,
  ): Promise<void> {
    // Stop any ongoing runs
    this.stopEvalsRun()
    this.evalsRunAbortController = new AbortController()

    this.dispatch({type: 'EVAL_SET_IS_RUNNING', payload: {isRunning: true}})

    const evalsConfig: Config = buildEvalsConfig(prompts, rows, evaluators, models)

    // Clear result
    this.dispatch({type: 'EVAL_CLEAR_RESULT'})

    // Start evals run
    try {
      for await (const row of runEval(
        evalsConfig,
        {
          api: {
            sendMessages: async (evalModelId, evalModelParameters, evalMessages, s) => {
              const startTime = Date.now()
              const evalModel = findModel(evalModelId, models)
              const tokenUsage = getDefaultTokenUsage()
              if (!evalModel) {
                if (evalModelId === 'gpt-4o') {
                  throw new Error(
                    `GPT-4o is disabled for this organization. Evaluations require GPT-4o to run. Ask your organization admin to enable GPT-4o to continue`,
                  )
                }
                throw new Error(`Model ${evalModelId} not found`)
              }

              const responseFormat = o1ModelNames.includes(evalModel.name) ? 'text' : promptResponseFormat || 'text'
              const jsonSchema =
                responseFormat === 'json_schema' && evalModel.name.toLowerCase() === 'gpt-4o'
                  ? promptJsonSchema
                  : undefined

              const response = await modelClient.sendNonStreamingMessage(
                evalModel,
                evalMessages,
                evalModelParameters as Record<string, unknown>,
                null, // sytem prompt
                responseFormat,
                jsonSchema, // json schema
                s,
              )
              tokenUsage.lastMessageInputTokens = response.tokenUsage?.inputTokens || 0
              tokenUsage.lastMessageOutputTokens = response.tokenUsage?.outputTokens || 0
              tokenUsage.lastMessageLatency = Date.now() - startTime

              return {
                completions: [response.message].map(x => ({
                  timestamp: x.timestamp,
                  role: x.role,
                  message: x.message as string, // We aren't support multi-modal content for now
                })),
                tokenUsage,
              }
            },
          },
        },
        this.evalsRunAbortController.signal,
      )) {
        this.dispatch({type: 'EVAL_UPDATE_RESULT_ROW', row})
      }
    } catch (e) {
      if (e instanceof DOMException && e.name === 'AbortError') {
        // If the run was aborted, ignore the error
        return
      }

      // eslint-disable-next-line no-console
      console.error(e)

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const message = (e as any)?.message || 'An error occurred while running evals.'
      this.dispatch({type: 'EVAL_SET_ERROR', payload: {error: message}})
    } finally {
      this.dispatch({type: 'EVAL_SET_IS_RUNNING', payload: {isRunning: false}})
    }
  }

  stopEvalsRun() {
    // Cancel any ongoing run
    if (this.evalsRunAbortController) {
      this.evalsRunAbortController.abort()
      this.evalsRunAbortController = null
    }

    // Immediately flip the state back to not running
    this.dispatch({type: 'EVAL_SET_IS_RUNNING', payload: {isRunning: false}})
  }

  evalsAddRow(row: EvalsRow) {
    this.dispatch({type: 'EVAL_ADD_ROW', row})
  }

  evalsUpdateRow(row: EvalsRow) {
    this.dispatch({type: 'EVAL_UPDATE_ROW', row})
  }

  evalsAddOrUpdateRow(row: EvalsRow) {
    this.dispatch({type: 'EVAL_ADD_OR_UPDATE_ROW', row})
  }

  evalsRemoveRow(id: string) {
    this.dispatch({type: 'EVAL_REMOVE_ROW', id})
  }

  evalsToggleRowSkip(id: string) {
    this.dispatch({type: 'EVAL_TOGGLE_ROW_SKIP', id})
  }

  evalsClear() {
    this.dispatch({type: 'EVAL_CLEAR'})
  }

  evalsAddEvaluator(evaluator: EvaluatorState) {
    this.dispatch({type: 'EVAL_ADD_EVALUATOR', evaluator})
  }

  evalsUpdateEvaluator(index: number, evaluator: EvaluatorCfg) {
    this.dispatch({type: 'EVAL_UPDATE_EVALUATOR', payload: {index, evaluator}})
  }

  evalsRemoveEvaluator(index: number) {
    this.dispatch({type: 'EVAL_REMOVE_EVALUATOR', index})
  }

  async sendMessage(
    model: RepoModel,
    modelClient: AzureModelClient,
    systemPrompt: string = '',
    text: string,
    parameters: Record<string, unknown> | undefined,
    setTokenUsage?: (tokenUsage: TokenUsage) => void,
    messagePairs: MessagePair[] = [],
    promptResponseFormat: ResponseFormat = 'text',
    promptJsonSchema?: string,
  ): Promise<void> {
    const validSystemPrompt = model.capabilities?.systemPrompt ? systemPrompt : ''

    const userMessage: Message = {
      timestamp: new Date(),
      role: 'user',
      message: text,
    } // getValidMessage(text, attachments, currentMessages, modelInputSchema, catalogData)

    if (!userMessage) return

    const responseFormat = o1ModelNames.includes(model.name) ? 'text' : promptResponseFormat || 'text'
    const jsonSchema =
      responseFormat === 'json_schema' && model.name.toLowerCase() === 'gpt-4o' ? promptJsonSchema : undefined

    const assistantMessagePlaceHolder = createAssistantMessage('')

    // For now always clear previous messages
    let messages = messagePairs.length > 0 ? [userMessage] : [userMessage, assistantMessagePlaceHolder]

    if (messagePairs.length > 0) {
      for (const pair of messagePairs) {
        messages = messages.concat([createAssistantMessage(pair.assistant), createUserMessage(pair.user)])
      }

      messages = messages.concat(assistantMessagePlaceHolder)
    }

    // Update the UI
    this.setMessages(messages)
    this.setIsLoading(true)
    const startTime = Date.now()

    const lastMessage = messages[messages.length - 1]
    // If the last message is a placeholder, we want to remove it before adding the new message
    const updatedMessages =
      lastMessage?.role === 'assistant' && lastMessage?.message === '' ? messages.slice(0, -1) : messages

    const tokenUsage = getDefaultTokenUsage()
    let response: IteratorResult<ModelClientSendMessageResponse, TokenUsageInfo | undefined> | undefined
    try {
      const generator = modelClient.sendMessage(
        0, // Panel is ignored for this view
        model,
        messages,
        parameters || {},
        validSystemPrompt,
        responseFormat,
        jsonSchema,
      )
      // Send the message to the model
      while (!(response = await generator.next()).done) {
        this.setMessages([
          ...updatedMessages,
          {
            role: response.value.message.role,
            message: response.value.message.message as string, // For now we're only supporting text
            timestamp: response.value.message.timestamp,
          },
        ])

        if (response.value.reachedMaxTokens) {
          throw new CompletionTokensLimitReachedResponseError()
        }
        tokenUsage.lastMessageOutputTokens += 1
        setTokenUsage?.(tokenUsage)
      }

      tokenUsage.lastMessageOutputTokens += response.value?.outputTokens || 0
      tokenUsage.lastMessageInputTokens += response.value?.inputTokens || 0
      setTokenUsage?.(tokenUsage)
    } catch (error: unknown) {
      // Some errors result in different UI states
      if (error && typeof error === 'object' && 'message' in error && typeof error.message === 'string') {
        this.setMessages([...updatedMessages, createErrorMessage(error.message)])

        // TODO: Error handling
        // if (error?.canRetry) this.setChatInput(index, userMessage.message)
      } else {
        this.setMessages([...updatedMessages, createErrorMessage('An error occurred. Please try again.')])
      }
    }

    this.setIsLoading(false)
    tokenUsage.lastMessageLatency = Date.now() - startTime
    setTokenUsage?.(tokenUsage)
  }
}
