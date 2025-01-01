import type {Dispatch} from 'react'
import type {AzureModelClient} from './azure-model-client'
import type {
  MessageContent,
  ModelDetails,
  ModelParameterValue,
  ModelState,
  PlaygroundMessage,
  PlaygroundResponseFormat,
  PlaygroundState,
  PlaygroundStateAction,
  TokenUsage,
  UsageStats,
  ModelClientSendMessageResponse,
  TokenUsageInfo,
} from '../types'

import {clearPlaygroundLocalStorage} from './playground-local-storage'
import {ModelClientError, o1ModelNames} from './playground-types'
import {
  defaultResponseFormat,
  getModelState,
  validateAndFilterParameters,
  validateSystemPrompt,
  getDefaultUsageStats,
} from './model-state'
import {createAssistantMessage, createErrorMessage, getValidMessage} from './message-content-helper'
import {searchTool} from './rag-index-manager'
import {getDefaultTokenUsage, updateTokenUsage} from './model-usage'

// This helper function allows us to encapsulate a lot of repetitive logic in a single function
const applyModelStatePayload = (
  state: PlaygroundState,
  {index, ...payload}: Partial<ModelState> & {index: number},
): PlaygroundState => ({
  ...state,
  models: state.models.map((modelState, i) => (i === index ? {...modelState, ...payload} : modelState)),
})

export function tasksReducer(state: PlaygroundState, {type, payload}: PlaygroundStateAction): PlaygroundState {
  switch (type) {
    /* These actions are all related to the modelState */
    case 'SET_IS_LOADING':
    case 'SET_MESSAGES':
    case 'SET_PARAMETERS':
    case 'SET_SYSTEM_PROMPT':
    case 'SET_IS_USE_INDEX_SELECTED':
    case 'SET_CHAT_CLOSED':
    case 'SET_CHAT_INPUT':
    case 'SET_PARAMETERS_HAS_CHANGES':
    case 'SET_RESPONSE_FORMAT':
    case 'SET_JSON_SCHEMA':
    case 'SET_TOKEN_USAGE':
    case 'SET_USAGE_STATS':
      return applyModelStatePayload(state, payload)
    case 'INCREMENT_TOKEN_USAGE': {
      const {index} = payload
      const modelState = state.models[index]
      if (!modelState) return state
      return applyModelStatePayload(state, {
        index,
        tokenUsage: {
          ...modelState.tokenUsage,
          lastMessageOutputTokens: modelState.tokenUsage.lastMessageOutputTokens + 1,
        },
      })
    }
    case 'SET_MODEL_STATE': {
      // Update the model if the index exists, otherwise add it
      const {index, modelState} = payload

      return state.models[index]
        ? applyModelStatePayload(state, {index, ...modelState})
        : {...state, models: [...state.models, modelState]}
    }
    case 'REMOVE_MODEL':
      return {
        ...state,
        models: state.models.filter((_, index) => index !== payload.index),
      }
    /* These actions are related to the playground state */
    case 'SET_SYNC_INPUTS':
      return {...state, ...payload}
    default:
      return state
  }
}

export const Panel = {
  Main: 0,
  Side: 1,
} as const

export type Panel = (typeof Panel)[keyof typeof Panel]

export class PlaygroundManager {
  dispatch: Dispatch<PlaygroundStateAction>

  constructor(dispatch: Dispatch<PlaygroundStateAction>) {
    this.dispatch = dispatch
  }

  setParameters = (index: number, parameters: Record<string, ModelParameterValue>) => {
    this.dispatch({type: 'SET_PARAMETERS', payload: {index, parameters}})
  }

  setChatInput = (index: number, chatInput: MessageContent) => {
    this.dispatch({type: 'SET_CHAT_INPUT', payload: {index, chatInput}})
  }

  setSystemPrompt = (index: number, systemPrompt: string) => {
    this.dispatch({type: 'SET_SYSTEM_PROMPT', payload: {index, systemPrompt}})
  }

  setResponseFormat = (index: number, responseFormat: PlaygroundResponseFormat) => {
    this.dispatch({type: 'SET_RESPONSE_FORMAT', payload: {index, responseFormat}})
  }

  setJsonSchema = (index: number, jsonSchema: string) => {
    this.dispatch({type: 'SET_JSON_SCHEMA', payload: {index, jsonSchema}})
  }

  setIsUseIndexSelected = (index: number, isUseIndexSelected: boolean) => {
    this.dispatch({type: 'SET_IS_USE_INDEX_SELECTED', payload: {index, isUseIndexSelected}})
  }

  setMessages = (index: number, messages: PlaygroundMessage[]) => {
    this.dispatch({type: 'SET_MESSAGES', payload: {index, messages}})
  }

  setIsLoading = (index: number, isLoading: boolean) => {
    this.dispatch({type: 'SET_IS_LOADING', payload: {index, isLoading}})
  }

  setChatClosed = (index: number, chatClosed: boolean) => {
    this.dispatch({type: 'SET_CHAT_CLOSED', payload: {index, chatClosed}})
  }

  setParametersHasChanges = (index: number, parametersHasChanges: boolean) => {
    this.dispatch({type: 'SET_PARAMETERS_HAS_CHANGES', payload: {index, parametersHasChanges}})
  }

  setTokenUsage = (index: number, tokenUsage: TokenUsage) => {
    this.dispatch({type: 'SET_TOKEN_USAGE', payload: {index, tokenUsage}})
  }

  setUsageStats(index: number, usageStats: UsageStats) {
    this.dispatch({type: 'SET_USAGE_STATS', payload: {index, usageStats}})
  }

  incrementTokenUsage(index: number) {
    this.dispatch({type: 'INCREMENT_TOKEN_USAGE', payload: {index}})
  }

  resetHistory = (index: number) => {
    // For now we save messages for the main model only
    if (index === Panel.Main) {
      clearPlaygroundLocalStorage()
    }
    this.setMessages(index, [])
    this.setChatClosed(index, false)
    this.setTokenUsage(index, getDefaultTokenUsage())
    this.setUsageStats(index, getDefaultUsageStats())
  }

  async sendMessage(
    index: number,
    modelState: ModelState,
    modelClient: AzureModelClient,
    text: string,
    attachments: string[] = [],
  ): Promise<void> {
    const {
      parameters,
      modelInputSchema = {},
      systemPrompt,
      messages: currentMessages,
      catalogData,
      isUseIndexSelected,
    } = modelState

    const {parameters: schemaParameters = []} = modelInputSchema

    const responseFormat = o1ModelNames.includes(modelState.catalogData.name)
      ? defaultResponseFormat
      : modelState.responseFormat || defaultResponseFormat

    const jsonSchema =
      responseFormat === 'json_schema' && modelState.catalogData.name.toLowerCase() === 'gpt-4o'
        ? modelState.jsonSchema
        : undefined

    // Validate all the inputs against the model schema
    const validParams = validateAndFilterParameters(schemaParameters, parameters)
    if (isUseIndexSelected) validParams.tools = [searchTool]
    const validPrompt = validateSystemPrompt(modelInputSchema, systemPrompt)
    const userMessage = getValidMessage(text, attachments, currentMessages, modelInputSchema, catalogData)

    if (!userMessage) return

    const assistantMessagePlaceHolder = createAssistantMessage('')

    // Add the user message and placeholder to the chat history
    const messages = [...currentMessages, userMessage, assistantMessagePlaceHolder]

    // Update the UI
    this.setMessages(index, messages)
    this.setIsLoading(index, true)
    const startTime = Date.now()
    const lastMessage = messages[messages.length - 1]
    // If the last message is a placeholder, we want to remove it before adding the new message
    const updatedMessages =
      lastMessage?.role === 'assistant' && lastMessage?.message === '' ? messages.slice(0, -1) : messages

    let response: IteratorResult<ModelClientSendMessageResponse, TokenUsageInfo | undefined> | undefined
    try {
      // Send the message to the model
      const generator = modelClient.sendMessage(
        index,
        catalogData,
        messages,
        validParams,
        validPrompt,
        responseFormat,
        jsonSchema,
      )
      while (!(response = await generator.next()).done) {
        this.setMessages(index, [...updatedMessages, response.value.message])
        this.incrementTokenUsage(index)
      }
      this.setTokenUsage(index, updateTokenUsage(modelState.tokenUsage, response.value))
    } catch (error: unknown) {
      // Some errors result in different UI states
      if (error instanceof ModelClientError) {
        if (response && response.value && 'message' in response.value && response.value.message) {
          this.setMessages(index, [...updatedMessages, response.value.message, createErrorMessage(error.message)])
        } else {
          this.setMessages(index, [...updatedMessages, createErrorMessage(error.message)])
        }

        if (error?.canRetry) this.setChatInput(index, userMessage.message)
        if (error?.tokenLimitReached) this.setChatClosed(index, true)
      } else {
        if (response && response.value && 'message' in response.value && response.value.message) {
          this.setMessages(index, [
            ...updatedMessages,
            response.value.message,
            createErrorMessage('An error occurred. Please try again.'),
          ])
        } else {
          this.setMessages(index, [...updatedMessages, createErrorMessage('An error occurred. Please try again.')])
        }
      }
    }

    const timeDiff = Date.now() - startTime
    this.setUsageStats(index, {
      lastMessageLatency: timeDiff,
      totalLatency: modelState.usageStats.totalLatency + timeDiff,
    })

    this.setIsLoading(index, false)
  }

  setModelState(index: number, modelState: ModelState) {
    this.dispatch({type: 'SET_MODEL_STATE', payload: {index, modelState}})
  }

  removeModel(index: number) {
    this.dispatch({type: 'REMOVE_MODEL', payload: {index}})
  }

  resetParamsAndSystemPrompt(index: number, modelDetails: ModelDetails) {
    const defaultModelState = getModelState(modelDetails)

    this.setParameters(index, defaultModelState.parameters)
    this.setSystemPrompt(index, defaultModelState.systemPrompt)
    this.setResponseFormat(index, defaultModelState.responseFormat)
    this.setJsonSchema(index, defaultModelState.jsonSchema || '')
    this.setParametersHasChanges(index, false)
  }

  setSyncInputs(syncInputs: boolean) {
    this.dispatch({type: 'SET_SYNC_INPUTS', payload: {syncInputs}})
  }
}
