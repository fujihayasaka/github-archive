import {verifiedFetch} from '@github-ui/verified-fetch'
import {createContext, useContext, type Dispatch} from 'react'
import type {MessagePair, ModelDetails, ModelParameterValue, ModelState, PlaygroundMessage} from '../../types'
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
import {setPromptLocalStorage} from '../../utils/prompt-local-storage'
import {searchTool} from '../../utils/rag-index-manager'
import type {PromptState, PromptStateAction} from './prompt-state'

export const PromptManagerContext = createContext<PromptManager>({} as PromptManager)

export function usePromptManager() {
  return useContext(PromptManagerContext)
}

export function promptReducer(state: PromptState, action: PromptStateAction): PromptState {
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

    case 'SET_VARIABLES':
      return returnAndSetLocalStorage({
        ...state,
        variables: action.payload.variables,
      })

    case 'SET_MESSAGE_PAIRS': {
      return returnAndSetLocalStorage({
        ...state,
        messagePairs: action.payload.messagePairs,
      })
    }
  }
}

function returnAndSetLocalStorage(state: PromptState): PromptState {
  setPromptLocalStorage(state)
  return state
}

export class PromptManager {
  dispatch: Dispatch<PromptStateAction>

  constructor(dispatch: Dispatch<PromptStateAction>) {
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

  setVariables(variables: Record<string, string>) {
    this.dispatch({type: 'SET_VARIABLES', payload: {variables}})
  }

  clearUserSystemPrompt() {
    this.dispatch({type: 'CLEAR_PROMPTS_INPUT'})
  }

  clearUserSystemPromptAndVariables() {
    this.setVariables({})
    this.clearUserSystemPrompt()
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
