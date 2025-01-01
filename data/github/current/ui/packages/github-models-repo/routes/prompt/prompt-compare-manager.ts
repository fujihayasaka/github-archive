import type {AzureModelClient} from '@github-ui/github-models/AzureModelClient'
import type {Model} from '@github-ui/marketplace-common'
import {createContext, useContext, type Dispatch} from 'react'
import {buildEvalsConfig} from './evals-config'
import {runEval} from './evals-sdk'
import type {Config, DataRow, EvaluatorCfg} from './evals-sdk/config'
import {findModel} from './models'
import type {EvaluatorState, PromptCompareState, PromptCompareStateAction} from './prompt-compare-state'
import type {PromptConfig} from './prompts'
import type {EvalsRow, Message} from './types'
import {createAssistantMessage, createErrorMessage} from './utils/message-utils'

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
    case 'EVAL_ADD_ROW': {
      return {
        ...state,
        compare: {
          ...state.compare,
          rows: [...state.compare.rows, {...action.row, id: state.compare.rows.length.toString()} as EvalsRow],
        },
      }
    }
    case 'EVAL_UPDATE_ROW': {
      return {
        ...state,
        compare: {
          ...state.compare,
          rows: state.compare.rows.map(row => (row.id === action.row.id ? action.row : row)),
        },
      }
    }
    case 'EVAL_REMOVE_ROW': {
      return {
        ...state,
        compare: {
          ...state.compare,
          rows: state.compare.rows.filter(row => row.id !== action.id),
        },
      }
    }

    case 'EVAL_CLEAR': {
      return {
        ...state,
        prompts: state.prompts.slice(0, 1),
        compare: {rows: [], result: [], evaluators: [], isRunning: false},
      }
    }

    case 'EVAL_ADD_EVALUATOR': {
      return {
        ...state,
        compare: {...state.compare, evaluators: [...state.compare.evaluators, action.evaluator]},
      }
    }

    case 'EVAL_UPDATE_EVALUATOR': {
      return {
        ...state,
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
      return {...state, compare: {...state.compare, result: []}}
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

  resetHistory() {
    this.setMessages([])
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
    models: Model[],
    prompts: PromptConfig[],
    rows: DataRow[],
    evaluators: EvaluatorCfg[],
  ): Promise<void> {
    // Stop any ongoing runs
    this.stopEvalsRun()
    this.evalsRunAbortController = new AbortController()

    this.dispatch({type: 'EVAL_SET_IS_RUNNING', payload: {isRunning: true}})

    const evalsConfig: Config = buildEvalsConfig(prompts, rows, evaluators)

    // Clear result
    this.dispatch({type: 'EVAL_CLEAR_RESULT'})

    // Start evals run
    try {
      for await (const row of runEval(
        evalsConfig,
        {
          api: {
            sendMessages: async (evalModelId, evalModelParameters, evalMessages, s) => {
              const evalModel = findModel(evalModelId, models)
              if (!evalModel) {
                throw new Error(`Model ${evalModelId} not found`)
              }

              const response = await modelClient.sendNonStreamingMessage(
                evalModel,
                evalMessages,
                evalModelParameters as Record<string, unknown>,
                null, // sytem prompt
                'text',
                undefined, // json schema
                s,
              )

              return [response.message].map(x => ({
                timestamp: x.timestamp,
                role: x.role,
                message: x.message as string, // We aren't support multi-modal content for now
              }))
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

  evalsRemoveRow(id: string) {
    this.dispatch({type: 'EVAL_REMOVE_ROW', id})
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
    model: Model,
    modelClient: AzureModelClient,
    systemPrompt: string = '',
    text: string,
  ): Promise<void> {
    // Validate all the inputs against the model schema
    const validPrompt = systemPrompt // validateSystemPrompt(model, systemPrompt)
    const userMessage: Message = {
      timestamp: new Date(),
      role: 'user',
      message: text,
    } // getValidMessage(text, attachments, currentMessages, modelInputSchema, catalogData)

    if (!userMessage) return

    const assistantMessagePlaceHolder = createAssistantMessage('')

    // For now always clear previous messages
    const messages = [userMessage, assistantMessagePlaceHolder]

    // Update the UI
    this.setMessages(messages)
    this.setIsLoading(true)

    const lastMessage = messages[messages.length - 1]
    // If the last message is a placeholder, we want to remove it before adding the new message
    const updatedMessages =
      lastMessage?.role === 'assistant' && lastMessage?.message === '' ? messages.slice(0, -1) : messages

    try {
      // Send the message to the model
      for await (const response of modelClient.sendMessage(
        0, // Panel is ignored for this view
        model,
        messages,
        {},
        validPrompt,
        'text',
      )) {
        this.setMessages([
          ...updatedMessages,
          {
            role: response.message.role,
            message: response.message.message as string, // For now we're only supporting text
            timestamp: response.message.timestamp,
          },
        ])
      }
    } catch (error: unknown) {
      // Some errors result in different UI states
      if (error && typeof error === 'object' && 'message' in error && typeof error.message === 'string') {
        this.setMessages([...updatedMessages, createErrorMessage(error.message)])

        // TODO: Error handling
        // if (error?.canRetry) this.setChatInput(index, userMessage.message)
        // if (error?.tokenLimitReached) this.setChatClosed(index, true)
      } else {
        this.setMessages([...updatedMessages, createErrorMessage('An error occurred. Please try again.')])
      }
    }

    this.setIsLoading(false)
  }
}
