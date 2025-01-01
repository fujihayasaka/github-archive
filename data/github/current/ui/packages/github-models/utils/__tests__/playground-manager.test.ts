import {Panel, PlaygroundManager} from '../playground-manager'
import {
  mockGettingStarted,
  mockModel,
  mockModelInputSchema,
  mockModelState,
} from '../../routes/playground/__tests__/mocks'

import {PlaygroundAPIMessageAuthorValues} from '../../types'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {getModelState} from '../model-state'
import {createAssistantMessage, createErrorMessage, createUserMessage} from '../message-content-helper'
import type {AzureModelClient} from '../azure-model-client'
import {ModelClientError, TokenLimitReachedResponseError, TooManyRequestsError} from '../playground-types'
import {UI_STATE_KEY} from '../playground-local-storage'
import safeStorage from '@github-ui/safe-storage'

jest.mock('@github-ui/react-core/use-feature-flag')

const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
}))

const safeLocalStorage = safeStorage('localStorage')

const createManager = () => {
  const abortController = new AbortController()
  const dispatch = jest.fn()
  const manager = new PlaygroundManager(dispatch)
  mockVerifiedFetchJSON.mockResolvedValue({
    ok: true,
    statusText: 'OK',
    json: async () => mockModel,
  })
  return {abortController, dispatch, manager}
}

afterEach(() => {
  safeLocalStorage.removeItem(UI_STATE_KEY)
})

afterAll(() => {
  jest.clearAllMocks()
})

describe('PlaygroundManager', () => {
  describe('setParameters', () => {
    it('dispatches the updated parameters', () => {
      const {manager, dispatch} = createManager()
      const newParams = {
        param1: 'value1',
        param2: 'value2',
      }

      manager.setParameters(Panel.Main, newParams)

      expect(dispatch).toHaveBeenCalledTimes(1)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'SET_PARAMETERS',
        payload: {
          index: Panel.Main,
          parameters: newParams,
        },
      })
    })
  })

  describe('setChatInput', () => {
    it('dispatches the new chat input', () => {
      const {manager, dispatch} = createManager()
      const chatInput = 'Hello, world!'
      const index = Panel.Main

      manager.setChatInput(index, chatInput)

      expect(dispatch).toHaveBeenCalledTimes(1)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'SET_CHAT_INPUT',
        payload: {
          index,
          chatInput,
        },
      })
    })
  })

  describe('setSystemPrompt', () => {
    it('dispatches the new system prompt', () => {
      const {manager, dispatch} = createManager()
      const systemPrompt = 'Hello, world!'
      const index = Panel.Main

      manager.setSystemPrompt(index, systemPrompt)

      expect(dispatch).toHaveBeenCalledTimes(1)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'SET_SYSTEM_PROMPT',
        payload: {
          index,
          systemPrompt,
        },
      })
    })
  })

  describe('setResponseFormat', () => {
    it('dispatches the new response format', () => {
      const {manager, dispatch} = createManager()
      const responseFormat = 'json_object'
      const index = Panel.Main

      manager.setResponseFormat(index, responseFormat)

      expect(dispatch).toHaveBeenCalledTimes(1)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'SET_RESPONSE_FORMAT',
        payload: {
          index,
          responseFormat,
        },
      })
    })
  })

  describe('setJsonSchema', () => {
    it('dispatches the new json schema', () => {
      const {manager, dispatch} = createManager()
      const jsonSchema = '{"type": "object"}'
      const index = Panel.Main

      manager.setJsonSchema(index, jsonSchema)

      expect(dispatch).toHaveBeenCalledTimes(1)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'SET_JSON_SCHEMA',
        payload: {
          index,
          jsonSchema,
        },
      })
    })
  })

  describe('setIsUseIndexSelected', () => {
    it('dispatches the new isUseIndexSelected value', () => {
      const {manager, dispatch} = createManager()
      const isUseIndexSelected = true

      manager.setIsUseIndexSelected(Panel.Main, isUseIndexSelected)

      expect(dispatch).toHaveBeenCalledTimes(1)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'SET_IS_USE_INDEX_SELECTED',
        payload: {
          index: Panel.Main,
          isUseIndexSelected,
        },
      })
    })
  })

  describe('setSyncInputs', () => {
    it('dispatches the new sync inputs value', () => {
      const {manager, dispatch} = createManager()
      const syncInputs = true

      manager.setSyncInputs(syncInputs)

      expect(dispatch).toHaveBeenCalledTimes(1)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'SET_SYNC_INPUTS',
        payload: {syncInputs},
      })
    })
  })

  describe('setMessages', () => {
    it('dispatches the new messages', () => {
      const {manager, dispatch} = createManager()
      const messages = [
        {
          timestamp: new Date(),
          role: PlaygroundAPIMessageAuthorValues[0],
          message: 'Hello, world!',
        },
      ]
      const index = Panel.Main

      manager.setMessages(index, messages)

      expect(dispatch).toHaveBeenCalledTimes(1)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'SET_MESSAGES',
        payload: {
          index,
          messages,
        },
      })
    })
  })

  describe('setParametersHasChanges', () => {
    it('dispatches the new parameters has changes value', () => {
      const {manager, dispatch} = createManager()
      const parametersHasChanges = true
      const index = Panel.Main

      manager.setParametersHasChanges(index, parametersHasChanges)

      expect(dispatch).toHaveBeenCalledTimes(1)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'SET_PARAMETERS_HAS_CHANGES',
        payload: {
          index,
          parametersHasChanges,
        },
      })
    })
  })

  describe('setTokenUsage', () => {
    it('dispatches the new token usage', () => {
      const {manager, dispatch} = createManager()
      const tokenUsage = {
        lastMessageInputTokens: 1,
        lastMessageOutputTokens: 2,
        totalInputTokens: 3,
        totalOutputTokens: 4,
        lastMessageLatency: 5,
      }
      const index = Panel.Main

      manager.setTokenUsage(index, tokenUsage)

      expect(dispatch).toHaveBeenCalledTimes(1)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'SET_TOKEN_USAGE',
        payload: {
          index,
          tokenUsage,
        },
      })
    })
  })

  describe('setUsageStats', () => {
    it('dispatches the new usage stats', () => {
      const {manager, dispatch} = createManager()
      const usageStats = {
        lastMessageLatency: 1,
        totalLatency: 2,
      }
      const index = Panel.Main

      manager.setUsageStats(index, usageStats)

      expect(dispatch).toHaveBeenCalledTimes(1)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'SET_USAGE_STATS',
        payload: {
          index,
          usageStats,
        },
      })
    })
  })

  describe('incrementTokenUsage', () => {
    it('dispatches the increment token usage action', () => {
      const {manager, dispatch} = createManager()
      const index = Panel.Main

      manager.incrementTokenUsage(index)

      expect(dispatch).toHaveBeenCalledTimes(1)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'INCREMENT_TOKEN_USAGE',
        payload: {
          index,
        },
      })
    })
  })

  describe('resetHistory', () => {
    it('resets the history for the model', () => {
      const {manager, dispatch} = createManager()
      const index = 0
      const isOnMarketplace = undefined

      manager.resetHistory(index, isOnMarketplace)

      expect(dispatch).toHaveBeenCalledTimes(4)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'SET_MESSAGES',
        payload: {
          index,
          messages: [],
        },
      })
      expect(dispatch).toHaveBeenCalledWith({
        type: 'SET_CHAT_CLOSED',
        payload: {
          index,
          chatClosed: false,
        },
      })
    })
  })

  describe('sendMessage', () => {
    it('sends a message and receives a valid response', async () => {
      const {manager} = createManager()
      const message = 'Hello'
      const userMessage = createUserMessage(message)
      const response = createAssistantMessage('Hi, how can I help you today?')
      const mockModelClient = {
        sendMessage: jest.fn(async function* () {
          yield {message: response}
        }),
      } as unknown as AzureModelClient

      manager.setMessages = jest.fn()
      manager.setIsLoading = jest.fn()
      manager.setChatInput = jest.fn()
      manager.setChatClosed = jest.fn()
      manager.setIsLoading = jest.fn()

      await manager.sendMessage(Panel.Main, mockModelState, mockModelClient, message, [])

      expect(mockModelClient.sendMessage).toHaveBeenCalledTimes(1)
      expect(manager.setIsLoading).toHaveBeenCalledWith(Panel.Main, true)
      expect(manager.setMessages).toHaveBeenCalledWith(Panel.Main, [
        ...mockModelState.messages,
        {...userMessage, timestamp: expect.any(Date)},
        {...response, timestamp: expect.any(Date)},
      ])
      expect(manager.setChatInput).not.toHaveBeenCalled()
      expect(manager.setChatClosed).not.toHaveBeenCalled()
      expect(manager.setIsLoading).toHaveBeenCalledWith(Panel.Main, false)
    })

    it('sends a message and receives a ModelClientError', async () => {
      const {manager} = createManager()
      const message = 'Hello'
      const userMessage = createUserMessage(message)
      const placeholder = createAssistantMessage('')
      const error = new ModelClientError('ModelClientError message')
      const mockModelClient = {
        // eslint-disable-next-line require-yield
        sendMessage: jest.fn(async function* () {
          throw error
        }),
      } as unknown as AzureModelClient
      const response = createErrorMessage(error.message)

      manager.setMessages = jest.fn()
      manager.setIsLoading = jest.fn()
      manager.setChatInput = jest.fn()
      manager.setChatClosed = jest.fn()
      manager.setIsLoading = jest.fn()

      await manager.sendMessage(Panel.Main, mockModelState, mockModelClient, message, [])

      expect(mockModelClient.sendMessage).toHaveBeenCalledTimes(1)
      expect(manager.setIsLoading).toHaveBeenCalledWith(Panel.Main, true)
      expect(manager.setMessages).toHaveBeenCalledTimes(2)
      expect(manager.setMessages).toHaveBeenNthCalledWith(1, Panel.Main, [
        ...mockModelState.messages,
        {...userMessage, timestamp: expect.any(Date)},
        {...placeholder, timestamp: expect.any(Date)},
      ])
      expect(manager.setMessages).toHaveBeenNthCalledWith(2, Panel.Main, [
        ...mockModelState.messages,
        {...userMessage, timestamp: expect.any(Date)},
        {...response, timestamp: expect.any(Date)},
      ])
      expect(manager.setChatInput).not.toHaveBeenCalled()
      expect(manager.setChatClosed).not.toHaveBeenCalled()
      expect(manager.setIsLoading).toHaveBeenCalledWith(Panel.Main, false)
    })

    it('sends a message and receives a TooManyRequestsError', async () => {
      const {manager} = createManager()
      const message = 'Hello'
      const userMessage = createUserMessage(message)
      const placeholder = createAssistantMessage('')
      const error = new TooManyRequestsError('TooManyRequestsError message')
      const response = createErrorMessage(error.message)
      const mockModelClient = {
        // eslint-disable-next-line require-yield
        sendMessage: jest.fn(async function* () {
          throw error
        }),
      } as unknown as AzureModelClient

      manager.setMessages = jest.fn()
      manager.setIsLoading = jest.fn()
      manager.setChatInput = jest.fn()
      manager.setChatClosed = jest.fn()
      manager.setIsLoading = jest.fn()

      await manager.sendMessage(Panel.Main, mockModelState, mockModelClient, message, [])

      expect(mockModelClient.sendMessage).toHaveBeenCalledTimes(1)
      expect(manager.setIsLoading).toHaveBeenCalledWith(Panel.Main, true)
      expect(manager.setMessages).toHaveBeenCalledTimes(2)
      expect(manager.setMessages).toHaveBeenNthCalledWith(1, Panel.Main, [
        ...mockModelState.messages,
        {...userMessage, timestamp: expect.any(Date)},
        {...placeholder, timestamp: expect.any(Date)},
      ])
      expect(manager.setMessages).toHaveBeenNthCalledWith(2, Panel.Main, [
        ...mockModelState.messages,
        {...userMessage, timestamp: expect.any(Date)},
        {...response, timestamp: expect.any(Date)},
      ])
      expect(manager.setChatInput).toHaveBeenCalledWith(Panel.Main, message)
      expect(manager.setChatClosed).not.toHaveBeenCalled()
      expect(manager.setIsLoading).toHaveBeenCalledWith(Panel.Main, false)
    })

    it('sends a message and receives a TokenLimitReachedResponseError', async () => {
      const {manager} = createManager()
      const message = 'Hello'
      const userMessage = createUserMessage(message)
      const placeholder = createAssistantMessage('')
      const error = new TokenLimitReachedResponseError()
      const response = createErrorMessage(error.message)
      const mockModelClient = {
        // eslint-disable-next-line require-yield
        sendMessage: jest.fn(async function* () {
          throw error
        }),
      } as unknown as AzureModelClient

      manager.setMessages = jest.fn()
      manager.setIsLoading = jest.fn()
      manager.setChatInput = jest.fn()
      manager.setChatClosed = jest.fn()
      manager.setIsLoading = jest.fn()

      await manager.sendMessage(Panel.Main, mockModelState, mockModelClient, message, [])

      expect(mockModelClient.sendMessage).toHaveBeenCalledTimes(1)
      expect(manager.setIsLoading).toHaveBeenCalledWith(Panel.Main, true)
      expect(manager.setMessages).toHaveBeenCalledTimes(2)
      expect(manager.setMessages).toHaveBeenNthCalledWith(1, Panel.Main, [
        ...mockModelState.messages,
        {...userMessage, timestamp: expect.any(Date)},
        {...placeholder, timestamp: expect.any(Date)},
      ])
      expect(manager.setMessages).toHaveBeenNthCalledWith(2, Panel.Main, [
        ...mockModelState.messages,
        {...userMessage, timestamp: expect.any(Date)},
        {...response, timestamp: expect.any(Date)},
      ])
      expect(manager.setChatInput).not.toHaveBeenCalled()
      expect(manager.setChatClosed).toHaveBeenCalledWith(Panel.Main, true)
      expect(manager.setIsLoading).toHaveBeenCalledWith(Panel.Main, false)
    })

    it('sends a message and receives a generic Error', async () => {
      const {manager} = createManager()
      const message = 'Hello'
      const userMessage = createUserMessage(message)
      const placeholder = createAssistantMessage('')
      const error = new Error('Generic Error')
      const response = createErrorMessage(error.message)
      const mockModelClient = {
        // eslint-disable-next-line require-yield
        sendMessage: jest.fn(async function* () {
          throw error
        }),
      } as unknown as AzureModelClient

      manager.setMessages = jest.fn()
      manager.setIsLoading = jest.fn()
      manager.setChatInput = jest.fn()
      manager.setChatClosed = jest.fn()
      manager.setIsLoading = jest.fn()

      await manager.sendMessage(Panel.Main, mockModelState, mockModelClient, message, [])

      expect(mockModelClient.sendMessage).toHaveBeenCalledTimes(1)
      expect(manager.setIsLoading).toHaveBeenCalledWith(Panel.Main, true)
      expect(manager.setMessages).toHaveBeenCalledTimes(2)
      expect(manager.setMessages).toHaveBeenNthCalledWith(1, Panel.Main, [
        ...mockModelState.messages,
        {...userMessage, timestamp: expect.any(Date)},
        {...placeholder, timestamp: expect.any(Date)},
      ])
      expect(manager.setMessages).toHaveBeenNthCalledWith(2, Panel.Main, [
        ...mockModelState.messages,
        {...userMessage, timestamp: expect.any(Date)},
        {...response, message: 'An error occurred. Please try again.', timestamp: expect.any(Date)},
      ])
      expect(manager.setChatInput).not.toHaveBeenCalled()
      expect(manager.setChatClosed).not.toHaveBeenCalled()
      expect(manager.setIsLoading).toHaveBeenCalledWith(Panel.Main, false)
    })

    it('sends a message and receives an Error mid-response', async () => {
      const {manager} = createManager()
      const message = 'Hello'
      const userMessage = createUserMessage(message)
      const placeholder = createAssistantMessage('')
      const partialResponse = createAssistantMessage('The answer to your question is')
      const error = new Error('Generic Error')
      const response = createErrorMessage(error.message)
      const mockModelClient = {
        sendMessage: jest.fn(async function* () {
          yield {message: partialResponse}
          throw error
        }),
      } as unknown as AzureModelClient

      manager.setMessages = jest.fn()
      manager.setIsLoading = jest.fn()
      manager.setChatInput = jest.fn()
      manager.setChatClosed = jest.fn()
      manager.setIsLoading = jest.fn()

      await manager.sendMessage(Panel.Main, mockModelState, mockModelClient, message, [])

      expect(mockModelClient.sendMessage).toHaveBeenCalledTimes(1)
      expect(manager.setIsLoading).toHaveBeenCalledWith(Panel.Main, true)
      expect(manager.setMessages).toHaveBeenCalledTimes(3)
      expect(manager.setMessages).toHaveBeenNthCalledWith(1, Panel.Main, [
        ...mockModelState.messages,
        {...userMessage, timestamp: expect.any(Date)},
        {...placeholder, timestamp: expect.any(Date)},
      ])
      expect(manager.setMessages).toHaveBeenNthCalledWith(3, Panel.Main, [
        ...mockModelState.messages,
        {...userMessage, timestamp: expect.any(Date)},
        {...partialResponse, timestamp: expect.any(Date)},
        {...response, message: 'An error occurred. Please try again.', timestamp: expect.any(Date)},
      ])
      expect(manager.setChatInput).not.toHaveBeenCalled()
      expect(manager.setChatClosed).not.toHaveBeenCalled()
      expect(manager.setIsLoading).toHaveBeenCalledWith(Panel.Main, false)
    })
  })

  describe('setModelState', () => {
    it('dispatches the new model state', () => {
      const {manager, dispatch} = createManager()
      const modelState = {
        ...mockModelState,
        catalogData: mockModel,
      }

      manager.setModelState(Panel.Side, modelState)

      expect(dispatch).toHaveBeenCalledTimes(1)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'SET_MODEL_STATE',
        payload: {
          index: Panel.Side,
          modelState,
        },
      })
    })
  })

  describe('removeModel', () => {
    it('dispatches the action and stops streaming', () => {
      const {manager, dispatch} = createManager()
      manager.removeModel(Panel.Side)

      expect(dispatch).toHaveBeenCalledTimes(1)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'REMOVE_MODEL',
        payload: {index: Panel.Side},
      })
    })
  })

  describe('resetParamsAndSystemPrompt', () => {
    it('resets the parameters, system prompt and response format to the defaults of the model provided', () => {
      const {manager} = createManager()
      manager.setParameters = jest.fn()
      manager.setSystemPrompt = jest.fn()
      manager.setResponseFormat = jest.fn()
      manager.setJsonSchema = jest.fn()

      const modelDetails = {
        catalogData: mockModel,
        modelInputSchema: mockModelInputSchema,
        gettingStarted: mockGettingStarted,
      }
      const modelStateDefaults = getModelState(modelDetails)

      manager.resetParamsAndSystemPrompt(Panel.Main, modelDetails)

      expect(manager.setParameters).toHaveBeenCalledTimes(1)
      expect(manager.setParameters).toHaveBeenCalledWith(Panel.Main, modelStateDefaults.parameters)
      expect(manager.setSystemPrompt).toHaveBeenCalledTimes(1)
      expect(manager.setSystemPrompt).toHaveBeenCalledWith(Panel.Main, modelStateDefaults.systemPrompt)
      expect(manager.setResponseFormat).toHaveBeenCalledTimes(1)
      expect(manager.setResponseFormat).toHaveBeenCalledWith(Panel.Main, modelStateDefaults.responseFormat)
      expect(manager.setJsonSchema).toHaveBeenCalledTimes(1)
      expect(manager.setJsonSchema).toHaveBeenCalledWith(Panel.Main, modelStateDefaults.jsonSchema)
    })
  })
})
