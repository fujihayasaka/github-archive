import type {Model} from '@github-ui/marketplace-common'
import {createContext, useContext, type Dispatch} from 'react'
import type {
  EvalsRow,
  EvaluatorState,
  MessagePair,
  ModelDetails,
  ModelParameterValue,
  ModelState,
  PlaygroundMessage,
} from '../../types'
import type {AzureModelClient} from '../../utils/azure-model-client'
import {
  createAssistantMessage,
  createErrorMessage,
  createUserMessage,
  getValidMessage,
} from '../../utils/message-content-helper'
import {
  combineParamsWithModel,
  defaultResponseFormat,
  getModelState,
  validateAndFilterParameters,
  validateSystemPrompt,
} from '../../utils/model-state'
import {Panel} from '../../utils/playground-manager'
import {ModelClientError} from '../../utils/playground-types'
import {setPromptEvalsLocalStorage} from '../../utils/prompt-evals-local-storage'
import {searchTool} from '../../utils/rag-index-manager'
import {buildEvalsConfig} from './evals-config'
import {runEval} from './evals-sdk'
import type {Config, DataRow, EvaluatorCfg} from './evals-sdk/config'
import type {Result} from './evals-sdk/result'
import type {PromptEvalsState, PromptEvalsStateAction} from './prompt-evals-state'
import {verifiedFetch} from '@github-ui/verified-fetch'

export const PromptEvalsManagerContext = createContext<PromptEvalsManager>({} as PromptEvalsManager)

export function usePromptEvalsManager() {
  return useContext(PromptEvalsManagerContext)
}

export function promptEvalsReducer(state: PromptEvalsState, action: PromptEvalsStateAction): PromptEvalsState {
  switch (action.type) {
    case 'SET_IS_LOADING':
      return {
        ...state,
        model: {...state.model, isLoading: action.payload.isLoading},
      }
    case 'SET_MESSAGES':
      return {
        ...state,
        model: {...state.model, messages: action.payload.messages},
      }
    case 'SET_PARAMETERS': {
      returnAndSetLocalStorage({...state, parameters: action.payload.parameters})
      return {
        ...state,
        model: {...state.model, parameters: action.payload.parameters},
      }
    }
    case 'SET_PARAMETERS_HAS_CHANGES':
      return {
        ...state,
        model: {...state.model, parametersHasChanges: action.payload.parametersHasChanges},
      }
    case 'SET_SYSTEM_PROMPT': {
      const updatedSystemPrompt = {...state, systemPrompt: action.payload.systemPrompt}
      return returnAndSetLocalStorage(updatedSystemPrompt)
    }
    case 'SET_MODEL_STATE': {
      const {modelState} = action.payload

      return {
        ...state,
        model: modelState,
      }
    }
    case 'SET_PROMPT_INPUT': {
      return returnAndSetLocalStorage({...state, prompt: action.payload.prompt})
    }
    case 'CLEAR_PROMPTS_INPUT': {
      return returnAndSetLocalStorage({...state, prompt: '', systemPrompt: ''})
    }
    case 'SET_PROMPT_FEEDBACK_BANNER_DISMISSED': {
      return {...state, promptFeedbackBannerDismissed: action.payload.dismissed}
    }
    case 'EVAL_ADD_ROW': {
      const updatedRows = {
        ...state,
        evals: {...state.evals, rows: [...state.evals.rows, {...action.row, id: state.evals.rows.length} as EvalsRow]},
      }
      return returnAndSetLocalStorage(updatedRows)
    }
    case 'EVAL_UPDATE_ROW': {
      const updatedRows = {
        ...state,
        evals: {
          ...state.evals,
          rows: state.evals.rows.map(row => (row.id === action.row.id ? action.row : row)),
        },
      }
      return returnAndSetLocalStorage(updatedRows)
    }
    case 'EVAL_REMOVE_ROW': {
      const updatedRows = {
        ...state,
        evals: {
          ...state.evals,
          rows: state.evals.rows.filter(row => row.id !== action.id),
        },
      }
      return returnAndSetLocalStorage(updatedRows)
    }
    case 'EVAL_CLEAR': {
      const updatedEvals = {...state, evals: {rows: [], result: [], evaluators: [], isRunning: false}}
      return returnAndSetLocalStorage(updatedEvals)
    }
    case 'EVAL_ADD_EVALUATOR': {
      const updatedEvaluators = {
        ...state,
        evals: {...state.evals, evaluators: [...state.evals.evaluators, action.evaluator]},
      }
      return returnAndSetLocalStorage(updatedEvaluators)
    }
    case 'EVAL_UPDATE_EVALUATOR': {
      const updatedEvaluators = {
        ...state,
        evals: {
          ...state.evals,
          evaluators: state.evals.evaluators.map((evaluator, i) =>
            i === action.payload.index
              ? {
                  ...evaluator,
                  config: action.payload.evaluator,
                }
              : evaluator,
          ),
        },
      }
      return returnAndSetLocalStorage(updatedEvaluators)
    }
    case 'EVAL_REMOVE_EVALUATOR': {
      const updatedEvaluators = {
        ...state,
        evals: {
          ...state.evals,
          evaluators: state.evals.evaluators.filter((_, i) => i !== action.index),
          result: state.evals.result.map(row => ({...row, evals: row.evals.filter((_, i) => i !== action.index)})),
        },
      }
      return returnAndSetLocalStorage(updatedEvaluators)
    }
    case 'EVAL_SET_IS_RUNNING':
      return {
        ...state,
        evals: {
          ...state.evals,
          isRunning: action.payload.isRunning,
        },
      }
    case 'EVAL_SET_RESULT': {
      const updatedResult = {...state, evals: {...state.evals, result: action.result}}
      return returnAndSetLocalStorage(updatedResult)
    }
    case 'EVAL_UPDATE_RESULT_ROW': {
      let existingIndex = state.evals.result.indexOf(action.row)
      if (existingIndex === -1) {
        existingIndex = state.evals.result.length
      }
      return {
        ...state,
        evals: {
          ...state.evals,
          result: [
            ...state.evals.result.slice(0, existingIndex),
            action.row,
            ...state.evals.result.slice(existingIndex + 1),
          ],
        },
      }
    }
    case 'EVAL_SET_VARIABLES':
      return returnAndSetLocalStorage({
        ...state,
        variables: action.payload.variables,
      })

    case 'EVAL_SET_ERROR':
      return {
        ...state,
        error: action.payload.error,
      }
    case 'SET_MESSAGE_PAIRS': {
      return returnAndSetLocalStorage({
        ...state,
        messagePairs: action.payload.messagePairs,
      })
    }
  }
}

function returnAndSetLocalStorage(state: PromptEvalsState): PromptEvalsState {
  setPromptEvalsLocalStorage(state)
  return state
}

export class PromptEvalsManager {
  dispatch: Dispatch<PromptEvalsStateAction>

  private evalsRunAbortController: AbortController | null = null

  constructor(dispatch: Dispatch<PromptEvalsStateAction>) {
    this.dispatch = dispatch
  }

  updateModel(modelDetails: ModelDetails, currentModel: ModelState, keepParameters: boolean) {
    const keepEverything = currentModel?.catalogData.name === modelDetails.catalogData.name
    const keepParams = keepParameters || keepEverything

    const newModel = combineParamsWithModel({
      modelDetails,
      systemPromptOverride: keepParams ? currentModel?.systemPrompt : undefined,
      responseFormatOverride: keepParams ? currentModel?.responseFormat : undefined,
      messagesOverride: keepEverything ? currentModel?.messages : undefined,
      parametersOverride: keepParams ? currentModel?.parameters : undefined,
      chatInputOverride: currentModel?.chatInput,
    })

    this.setModelState(newModel)
  }

  setParameters(parameters: Record<string, ModelParameterValue>) {
    this.dispatch({type: 'SET_PARAMETERS', payload: {parameters}})
  }

  setParametersHasChanges(parametersHasChanges: boolean) {
    this.dispatch({type: 'SET_PARAMETERS_HAS_CHANGES', payload: {parametersHasChanges}})
  }

  setSystemPrompt(systemPrompt: string) {
    this.dispatch({type: 'SET_SYSTEM_PROMPT', payload: {systemPrompt}})
  }

  setMessages(messages: PlaygroundMessage[]) {
    this.dispatch({type: 'SET_MESSAGES', payload: {messages}})
  }

  setIsLoading(isLoading: boolean) {
    this.dispatch({type: 'SET_IS_LOADING', payload: {isLoading}})
  }

  setPromptInput(prompt: string) {
    this.dispatch({type: 'SET_PROMPT_INPUT', payload: {prompt}})
  }

  setMessagePairs(messagePairs: MessagePair[]) {
    this.dispatch({type: 'SET_MESSAGE_PAIRS', payload: {messagePairs}})
  }

  async dismissPromptFeedbackBanner() {
    // Hide banner immediately
    this.dispatch({type: 'SET_PROMPT_FEEDBACK_BANNER_DISMISSED', payload: {dismissed: true}})

    await verifiedFetch('/settings/dismiss-notice/github_models_prompt_feedback_banner', {
      method: 'POST',
    })
  }

  resetHistory() {
    this.setMessages([])
  }

  setError(error: string | undefined) {
    this.dispatch({type: 'EVAL_SET_ERROR', payload: {error}})
  }

  setVariables(variables: Record<string, string>) {
    this.dispatch({type: 'EVAL_SET_VARIABLES', payload: {variables}})
  }

  async startEvalsRun(
    model: ModelState,
    modelClient: AzureModelClient,
    models: Model[],
    systemPrompt: string | undefined,
    prompt: string,
    rows: DataRow[],
    evaluators: EvaluatorCfg[],
  ): Promise<void> {
    // Stop any ongoing runs
    this.stopEvalsRun()
    this.evalsRunAbortController = new AbortController()

    this.dispatch({type: 'EVAL_SET_IS_RUNNING', payload: {isRunning: true}})

    const evalsConfig: Config = buildEvalsConfig(model, systemPrompt, prompt, rows, evaluators)

    // Clear result
    this.dispatch({type: 'EVAL_SET_RESULT', result: []})

    // Start evals run
    try {
      for await (const row of runEval(
        evalsConfig,
        {
          api: {
            sendMessages: async (evalModelId, evalModelParameters, evalMessages, s) => {
              const evalModels = models.filter(m => m.id.startsWith(evalModelId))
              if (!evalModels || evalModels.length === 0) {
                throw new Error(`Model ${evalModelId} not found`)
              }

              // If multiple models match, order by id desc, and then select the first one
              const evalModel = evalModels.sort((a, b) => b.id.localeCompare(a.id))[0]!

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

  evalsRemoveRow(id: number) {
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

  evalsSetResult(result: Result) {
    this.dispatch({type: 'EVAL_SET_RESULT', result})
  }

  evalsClearUserSystemPrompt() {
    this.dispatch({type: 'CLEAR_PROMPTS_INPUT'})
  }

  evalsClearUserSystemPromptAndVariables() {
    this.setVariables({})
    this.evalsClearUserSystemPrompt()
  }

  async sendMessage(
    modelState: ModelState,
    modelClient: AzureModelClient,
    systemPrompt: string = '',
    text: string,
    attachments: string[] = [],
    messagePairs?: MessagePair[],
  ): Promise<void> {
    const {parameters, modelInputSchema = {}, messages: currentMessages, catalogData, isUseIndexSelected} = modelState

    const {parameters: schemaParameters = []} = modelInputSchema

    const responseFormat = modelState.catalogData.name.includes('o1')
      ? defaultResponseFormat
      : modelState.responseFormat || defaultResponseFormat

    // Validate all the inputs against the model schema
    const validParams = validateAndFilterParameters(schemaParameters, parameters)
    if (isUseIndexSelected) validParams.tools = [searchTool]
    const validPrompt = validateSystemPrompt(modelInputSchema, systemPrompt)
    const userMessage = getValidMessage(text, attachments, currentMessages, modelInputSchema, catalogData)

    if (!userMessage) return

    const assistantMessagePlaceHolder = createAssistantMessage('')

    // For now always clear previous messages
    let messages = messagePairs ? [userMessage] : [userMessage, assistantMessagePlaceHolder]

    if (messagePairs) {
      for (const pair of messagePairs) {
        messages = messages.concat([createAssistantMessage(pair.assistant), createUserMessage(pair.user)])
      }

      messages = messages.concat(assistantMessagePlaceHolder)
    }

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
        Panel.Main,
        catalogData,
        messages,
        validParams,
        validPrompt,
        responseFormat,
      )) {
        this.setMessages([...updatedMessages, response.message])
      }
    } catch (error: unknown) {
      // Some errors result in different UI states
      if (error instanceof ModelClientError) {
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

  setModelState(modelState: ModelState) {
    this.dispatch({type: 'SET_MODEL_STATE', payload: {modelState}})
  }

  resetParams(modelDetails: ModelDetails) {
    const defaultModelState = getModelState(modelDetails)

    this.setParameters(defaultModelState.parameters)
  }
}
