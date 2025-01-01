import {createContext, useContext, type Dispatch} from 'react'
import type {AzureModelClient} from './azure-model-client'
import type {
  GettingStarted,
  MessageContent,
  ModelDetails,
  ModelParameterValue,
  ModelState,
  PlaygroundMessage,
  PlaygroundResponseFormat,
  PlaygroundState,
  PlaygroundStateAction,
} from '../types'
import {ModelClientError} from './playground-types'
import {clearPlaygroundLocalStorage, PlaygroundLocalStorage} from './playground-local-storage'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {
  defaultResponseFormat,
  getModelStateDefaults,
  combineParamsWithModel,
  validateAndFilterParameters,
  validateSystemPrompt,
} from './model-state'
import {createErrorMessage, getValidMessage} from './message-content-helper'
import {searchTool} from './rag-index-manager'

export const PlaygroundManagerContext = createContext<PlaygroundManager>({} as PlaygroundManager)

export function usePlaygroundManager() {
  return useContext(PlaygroundManagerContext)
}

export function tasksReducer(state: PlaygroundState, action: PlaygroundStateAction): PlaygroundState {
  switch (action.type) {
    case 'SET_IS_LOADING':
      return {
        ...state,
        models: state.models.map((model, index) => {
          return index === action.payload.index ? {...model, isLoading: action.payload.isLoading} : model
        }),
      }
    case 'SET_MESSAGES':
      return {
        ...state,
        models: state.models.map((model, index) => {
          return index === action.payload.index ? {...model, messages: action.payload.messages} : model
        }),
      }
    case 'SET_PARAMETERS':
      return {
        ...state,
        models: state.models.map((model, index) => {
          return index === action.payload.index ? {...model, parameters: action.payload.parameters} : model
        }),
      }
    case 'SET_SYSTEM_PROMPT':
      return {
        ...state,
        models: state.models.map((model, index) => {
          return index === action.payload.index ? {...model, systemPrompt: action.payload.systemPrompt} : model
        }),
      }
    case 'SET_RESPONSE_FORMAT':
      return {
        ...state,
        models: state.models.map((model, index) => {
          return index === action.payload.index ? {...model, responseFormat: action.payload.responseFormat} : model
        }),
      }
    case 'SET_IS_USE_INDEX_SELECTED':
      return {
        ...state,
        models: state.models.map((model, index) => {
          return index === action.payload.index
            ? {...model, isUseIndexSelected: action.payload.isUseIndexSelected}
            : model
        }),
      }
    case 'CLEAR_LAST_PLACEHOLDER_MESSAGE': {
      const modelMessages = state.models[action.index]?.messages
      if (!modelMessages) return {...state}
      const lastMessage = modelMessages.slice(-1)[0]
      if (!lastMessage) return {...state}
      if (lastMessage.role === 'assistant' && lastMessage?.message === '') {
        return {
          ...state,
          models: state.models.map((model, index) => {
            if (index === action.index) {
              return {...model, messages: modelMessages.slice(0, -1)}
            } else {
              return model
            }
          }),
        }
      } else {
        return {...state}
      }
    }
    case 'SET_CHAT_CLOSED':
      return {
        ...state,
        models: state.models.map((model, index) => {
          return index === action.payload.index ? {...model, chatClosed: action.payload.chatClosed} : model
        }),
      }
    case 'SET_CHAT_INPUT':
      return {
        ...state,
        models: state.models.map((model, index) => {
          return index === action.payload.index ? {...model, chatInput: action.payload.chatInput} : model
        }),
      }
    case 'SET_PARAMETERS_HAS_CHANGES':
      return {
        ...state,
        models: state.models.map((model, index) => {
          return index === action.payload.index
            ? {...model, parametersHasChanges: action.payload.parametersHasChanges}
            : model
        }),
      }
    case 'SET_SELECTED_LANGUAGE':
      return {...state, selectedLanguage: action.selectedLanguage}
    case 'SET_SELECTED_SDK':
      return {...state, selectedSDK: action.selectedSDK}
    case 'SET_MODEL_STATE': {
      const {index, modelState} = action.payload

      if (state.models[index]) {
        return {
          ...state,
          models: state.models.map((currentModelState, i) => (i === index ? modelState : currentModelState)),
        }
      } else {
        return {
          ...state,
          models: [...state.models, modelState],
        }
      }
    }
    case 'REMOVE_MODEL':
      if (state.models.length === 1) return state
      return {
        ...state,
        models: state.models.filter((_, index) => {
          return index !== action.index
        }),
      }
    case 'SET_SYNC_INPUTS':
      return {
        ...state,
        syncInputs: action.syncInputs,
      }
  }
}

export enum Panel {
  Main = 0,
  Side = 1,
}

export class PlaygroundManager {
  dispatch: Dispatch<PlaygroundStateAction>

  localStorage = new PlaygroundLocalStorage()
  controller: AbortController | null = null

  constructor(dispatch: Dispatch<PlaygroundStateAction>) {
    this.dispatch = dispatch
  }

  updateMainModel(modelDetails: ModelDetails, currentModels: ModelState[], keepParameters: boolean) {
    const currentMainModel = currentModels[Panel.Main]
    // When a side model becomes the new main model (removing the main model), we want to persist the chat history and parameters always.
    const keepEverything = currentMainModel?.catalogData.name === modelDetails.catalogData.name
    const keepParams = keepParameters || keepEverything

    const newModel = combineParamsWithModel({
      modelDetails,
      systemPromptOverride: keepParams ? currentMainModel?.systemPrompt : undefined,
      responseFormatOverride: keepParams ? currentMainModel?.responseFormat : undefined,
      messagesOverride: keepEverything ? currentMainModel?.messages : undefined,
      parametersOverride: keepParams ? currentMainModel?.parameters : undefined,
      chatInputOverride: currentMainModel?.chatInput,
    })

    this.setModelState(Panel.Main, newModel)
  }

  setPreferredLanguageFromLocalStorage(gettingStarted: GettingStarted) {
    const savedLanguage = this.localStorage.uiState.preferredLanguage

    // Some languages are only available in the getting started section and not in the code sample view
    const languages = Object.entries(gettingStarted).reduce<string[]>((acc, [language, {sdks}]) => {
      // If a language has no samples, we don't want it in the list
      const hasSamples = Object.values(sdks).some(sdk => sdk.codeSamples && sdk.codeSamples.length > 0)
      return hasSamples ? [...acc, language] : acc
    }, [])

    if (languages.length > 0) {
      const language = (languages.includes(savedLanguage) ? savedLanguage : languages[0]) || ''
      const savedSdk = this.localStorage.uiState.preferredSdk
      this.setSelectedLanguage(gettingStarted, language, savedSdk)
    }
  }

  setSelectedLanguage(gettingStarted: GettingStarted, selectedLanguage: string, selectedSDK: string) {
    const languageSnippet = gettingStarted[selectedLanguage]

    if (languageSnippet) {
      this.localStorage.uiState = {...this.localStorage.uiState, preferredLanguage: selectedLanguage}
      this.dispatch({type: 'SET_SELECTED_LANGUAGE', selectedLanguage})

      const sdks = Object.keys(languageSnippet.sdks)
      const sdk = sdks.includes(selectedSDK) ? selectedSDK : sdks[0]
      if (sdk) this.setSelectedSDK(sdk)
    }
  }

  setSelectedSDK(selectedSDK: string) {
    this.localStorage.uiState = {...this.localStorage.uiState, preferredSdk: selectedSDK}
    this.dispatch({type: 'SET_SELECTED_SDK', selectedSDK})
  }

  setParameters(index: number, parameters: Record<string, ModelParameterValue>) {
    this.dispatch({type: 'SET_PARAMETERS', payload: {index, parameters}})
  }

  setChatInput(index: number, chatInput: MessageContent) {
    this.dispatch({type: 'SET_CHAT_INPUT', payload: {index, chatInput}})
  }

  setSystemPrompt(index: number, systemPrompt: string) {
    this.dispatch({type: 'SET_SYSTEM_PROMPT', payload: {index, systemPrompt}})
  }

  setResponseFormat(index: number, responseFormat: PlaygroundResponseFormat) {
    this.dispatch({type: 'SET_RESPONSE_FORMAT', payload: {index, responseFormat}})
  }

  setIsUseIndexSelected(index: number, isUseIndexSelected: boolean) {
    this.dispatch({type: 'SET_IS_USE_INDEX_SELECTED', payload: {index, isUseIndexSelected}})
  }

  setSyncInputs(syncInputs: boolean) {
    this.dispatch({type: 'SET_SYNC_INPUTS', syncInputs})
  }

  setMessages(index: number, messages: PlaygroundMessage[]) {
    this.dispatch({type: 'SET_MESSAGES', payload: {index, messages}})
  }

  clearLastPlaceholderMessage(index: number) {
    this.dispatch({type: 'CLEAR_LAST_PLACEHOLDER_MESSAGE', index})
  }

  setIsLoading(index: number, isLoading: boolean) {
    this.dispatch({type: 'SET_IS_LOADING', payload: {index, isLoading}})
  }

  setChatClosed(index: number, chatClosed: boolean) {
    this.dispatch({type: 'SET_CHAT_CLOSED', payload: {index, chatClosed}})
  }

  setParametersHasChanges(index: number, parametersHasChanges: boolean) {
    this.dispatch({type: 'SET_PARAMETERS_HAS_CHANGES', payload: {index, parametersHasChanges}})
  }

  resetHistory(index: number) {
    // For now we save messages for the main model only
    if (index === Panel.Main) {
      clearPlaygroundLocalStorage()
    }
    this.setMessages(index, [])
    this.setChatClosed(index, false)
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

    const responseFormat = modelState.catalogData.name.includes('o1')
      ? defaultResponseFormat
      : modelState.responseFormat || defaultResponseFormat

    // Validate all the inputs against the model schema
    const validParams = validateAndFilterParameters(schemaParameters, parameters)
    if (isUseIndexSelected) validParams.tools = [searchTool]
    const validPrompt = validateSystemPrompt(modelInputSchema, systemPrompt)
    const userMessage = getValidMessage(text, attachments, currentMessages, modelInputSchema, catalogData)

    if (!userMessage) return

    // Add the user message to the chat history
    const messages = [...currentMessages, userMessage]

    // Update the UI
    this.setMessages(index, messages)
    this.setIsLoading(index, true)

    try {
      // Send the message to the model
      for await (const message of modelClient.sendMessage(
        index,
        catalogData,
        messages,
        validParams,
        validPrompt,
        responseFormat,
      )) {
        this.clearLastPlaceholderMessage(index)
        this.setMessages(index, [...messages, message])
      }
    } catch (error: unknown) {
      // Some errors result in different UI states
      if (error instanceof ModelClientError) {
        this.setMessages(index, [...messages, createErrorMessage(error.message)])

        if (error?.canRetry) this.setChatInput(index, userMessage.message)
        if (error?.tokenLimitReached) this.setChatClosed(index, true)
      } else {
        this.setMessages(index, [...messages, createErrorMessage('An error occurred. Please try again.')])
      }
    }

    this.setIsLoading(index, false)
  }

  async getSideModel(modelName: string, currentModelState: ModelState, syncInputs = false) {
    if (this.controller) this.controller.abort() // Abort any previous requests
    this.controller = new AbortController()
    try {
      const res = await verifiedFetchJSON(`/marketplace/models/side_model?compare_to=${modelName}`, {
        signal: this.controller.signal,
      })
      if (!res.ok) throw new Error('Failed to fetch side model')
      const modelDetails = await res.json()
      const modelState = combineParamsWithModel({
        modelDetails,
        systemPromptOverride: syncInputs ? currentModelState.systemPrompt : undefined,
        responseFormatOverride: syncInputs ? currentModelState.responseFormat : undefined,
        parametersOverride: syncInputs ? currentModelState.parameters : undefined,
        chatInputOverride: syncInputs ? currentModelState.chatInput : undefined,
      })
      this.setModelState(Panel.Side, modelState)
      return {success: true}
    } catch {
      return {success: false}
    }
  }

  setModelState(index: number, modelState: ModelState) {
    this.dispatch({type: 'SET_MODEL_STATE', payload: {index, modelState}})
  }

  removeModel(index: number) {
    this.dispatch({type: 'REMOVE_MODEL', index})
  }

  resetParamsAndSystemPrompt(index: number, modelDetails: ModelDetails) {
    const defaultModelState = getModelStateDefaults(modelDetails)

    this.setParameters(index, defaultModelState.parameters)
    this.setSystemPrompt(index, defaultModelState.systemPrompt)
  }
}
