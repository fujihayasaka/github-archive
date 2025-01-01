import {Panel, PlaygroundManager} from '../playground-manager'
import {
  mockGettingStarted,
  mockModel,
  mockModelInputSchema,
  mockModelState,
} from '../../routes/playground/__tests__/mocks'
import {PlaygroundAPIMessageAuthorValues, type ShowModelGettingStartedPayloadLanguageEntry} from '../../types'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {getModelStateDefaults} from '../model-state'
import {createAssistantMessage, createErrorMessage, createUserMessage} from '../message-content-helper'
import type {AzureModelClient} from '../azure-model-client'
import {ModelClientError, TokenLimitReachedResponseError, TooManyRequestsError} from '../playground-types'

jest.mock('@github-ui/react-core/use-feature-flag')

const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
}))

const defaultLocalStorageUiState = {
  sidebarTab: 0,
  showSidebar: true,
  preferredLanguage: 'js',
  preferredSdk: '',
}

const mockModelDetails = {
  catalogData: {
    ...mockModel,
    name: 'new-model',
  },
  modelInputSchema: {
    ...mockModelInputSchema,
    version: '2.0',
  },
  gettingStarted: {
    javascript: {
      name: 'JavaScript',
      sdks: {
        'azure-ai-inference': {
          name: 'Azure AI Inference SDK',
          tocHeadings: [],
          content: '',
          codeSamples: '',
        },
      },
    },
  },
}

const createManager = () => {
  const abortController = new AbortController()
  const dispatch = jest.fn()
  const manager = new PlaygroundManager(dispatch)
  // Some of the functions set local storage values, so we need to reset it to defaults
  manager.localStorage.uiState = defaultLocalStorageUiState
  manager.controller = abortController
  mockVerifiedFetchJSON.mockResolvedValue({
    ok: true,
    statusText: 'OK',
    json: async () => mockModel,
  })
  return {abortController, dispatch, manager}
}

afterAll(() => {
  jest.clearAllMocks()
})

describe('PlaygroundManager', () => {
  describe('updateMainModel', () => {
    it('updates the model', () => {
      const {manager} = createManager()
      manager.setModelState = jest.fn()

      const keepParameters = false
      const expectedModelState = getModelStateDefaults(mockModelDetails)

      manager.updateMainModel(mockModelDetails, [mockModelState], keepParameters)

      expect(manager.setModelState).toHaveBeenCalledWith(Panel.Main, expectedModelState)
    })

    it('keeps the chat history and params when the side model becomes the main model', () => {
      const {manager} = createManager()
      manager.setModelState = jest.fn()

      const sideModelState = {
        ...mockModelState,
        catalogData: mockModelDetails.catalogData,
        modelInputSchema: mockModelDetails.modelInputSchema,
        gettingStarted: mockModelDetails.gettingStarted,
      }

      const expectedModelState = {
        ...getModelStateDefaults(mockModelDetails),
        messages: mockModelState.messages,
      }

      const keepParameters = false

      manager.updateMainModel(mockModelDetails, [sideModelState], keepParameters)

      expect(manager.setModelState).toHaveBeenCalledWith(Panel.Main, expectedModelState)
    })

    it('keeps the params when requested', () => {
      const {manager} = createManager()
      manager.setModelState = jest.fn()

      const oldModelState = {
        ...mockModelState,
        systemPrompt: 'old system prompt',
        parametersHasChanges: true,
      }

      const expectedModelState = {
        ...getModelStateDefaults(mockModelDetails),
        parameters: oldModelState.parameters,
        systemPrompt: oldModelState.systemPrompt,
        parametersHasChanges: oldModelState.parametersHasChanges,
      }

      const keepParameters = true

      manager.updateMainModel(mockModelDetails, [oldModelState], keepParameters)

      expect(manager.setModelState).toHaveBeenCalledWith(Panel.Main, expectedModelState)
    })
  })

  describe('setPreferredLanguageFromLocalStorage', () => {
    it('does nothing if GettingStarted is empty', () => {
      const {manager} = createManager()
      const setSelectedLanguageSpy = jest.spyOn(manager, 'setSelectedLanguage')

      manager.setPreferredLanguageFromLocalStorage({})

      expect(setSelectedLanguageSpy).not.toHaveBeenCalled()
    })

    it('returns nothing if none of the GettingStarted languages have codeSamples', () => {
      const {manager} = createManager()
      const setSelectedLanguageSpy = jest.spyOn(manager, 'setSelectedLanguage')

      manager.setPreferredLanguageFromLocalStorage({
        go: mockGettingStarted.go as ShowModelGettingStartedPayloadLanguageEntry,
      })

      expect(setSelectedLanguageSpy).not.toHaveBeenCalled()
    })

    describe('when local storage is empty', () => {
      it('selects the first language from GettingStarted', () => {
        const {manager} = createManager()
        const setSelectedLanguageSpy = jest.spyOn(manager, 'setSelectedLanguage')

        manager.setPreferredLanguageFromLocalStorage(mockGettingStarted)

        const expectedLanguage = 'python'
        // This is blank because it's set by localstorage, which is empty in this test
        const expectedSdk = ''

        expect(setSelectedLanguageSpy).toHaveBeenCalledWith(mockGettingStarted, expectedLanguage, expectedSdk)
      })
    })

    describe('when local storage is not empty', () => {
      it('gets the matching language from GettingStarted', () => {
        const {manager} = createManager()
        const setSelectedLanguageSpy = jest.spyOn(manager, 'setSelectedLanguage')

        const localStorageLanguage = 'javascript'
        const localStorageSdk = 'azure-javascript-sdk'

        manager.localStorage.uiState = {
          ...defaultLocalStorageUiState,
          preferredLanguage: localStorageLanguage,
          preferredSdk: localStorageSdk,
        }

        manager.setPreferredLanguageFromLocalStorage(mockGettingStarted)

        expect(setSelectedLanguageSpy).toHaveBeenCalledWith(mockGettingStarted, localStorageLanguage, localStorageSdk)
      })

      it('selects the first language from GettingStarted if the language from local storage does not match any', () => {
        const {manager} = createManager()
        const setSelectedLanguageSpy = jest.spyOn(manager, 'setSelectedLanguage')

        const localStorageLanguage = 'non-existent-language'
        const localStorageSdk = 'non-existent-sdk'

        manager.localStorage.uiState = {
          ...defaultLocalStorageUiState,
          preferredLanguage: localStorageLanguage,
          preferredSdk: localStorageSdk,
        }

        manager.setPreferredLanguageFromLocalStorage(mockGettingStarted)

        const expectedLanguage = 'python'

        expect(setSelectedLanguageSpy).toHaveBeenCalledWith(mockGettingStarted, expectedLanguage, localStorageSdk)
      })

      it('returns the first language from GettingStarted if the language from local storage matches, but that GettingStarted entry does not have any codeSamlpes', () => {
        const {manager} = createManager()
        const setSelectedLanguageSpy = jest.spyOn(manager, 'setSelectedLanguage')

        const localStorageLanguage = 'go'
        const localStorageSdk = 'azure-go-sdk'

        manager.localStorage.uiState = {
          ...defaultLocalStorageUiState,
          preferredLanguage: localStorageLanguage,
          preferredSdk: localStorageSdk,
        }

        manager.setPreferredLanguageFromLocalStorage(mockGettingStarted)

        const expectedLanguage = 'python'

        expect(setSelectedLanguageSpy).toHaveBeenCalledWith(mockGettingStarted, expectedLanguage, localStorageSdk)
      })
    })
  })

  describe('setSelectedLanguage', () => {
    it('updates local storage, sets the selected SDK, and dispatches the action', () => {
      const {manager, dispatch} = createManager()
      const selectedLanguage = 'javascript'
      const selectedSdk = 'azure-javascript-sdk'

      const spySetSelectedSDK = jest.spyOn(manager, 'setSelectedSDK')

      expect(manager.localStorage.uiState.preferredLanguage).toEqual(defaultLocalStorageUiState.preferredLanguage)

      manager.setSelectedLanguage(mockGettingStarted, selectedLanguage, selectedSdk)

      expect(manager.localStorage.uiState.preferredLanguage).toEqual(selectedLanguage)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'SET_SELECTED_LANGUAGE',
        selectedLanguage,
      })
      expect(spySetSelectedSDK).toHaveBeenCalledWith(selectedSdk)
    })

    it('updates local storage and dispatches the action, but does not set selectedSDK when no sdks exist', () => {
      const {manager, dispatch} = createManager()
      const selectedLanguage = 'csharp'
      const selectedSdk = 'non-existent-sdk'

      const spySetSelectedSDK = jest.spyOn(manager, 'setSelectedSDK')

      expect(manager.localStorage.uiState.preferredLanguage).toEqual(defaultLocalStorageUiState.preferredLanguage)

      manager.setSelectedLanguage(mockGettingStarted, selectedLanguage, selectedSdk)

      expect(manager.localStorage.uiState.preferredLanguage).toEqual(selectedLanguage)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'SET_SELECTED_LANGUAGE',
        selectedLanguage,
      })
      expect(spySetSelectedSDK).not.toHaveBeenCalled()
    })

    it('updates local storage, dispatches the action, and sets the selectedSDK to the first available when there is no match', () => {
      const {manager, dispatch} = createManager()
      const selectedLanguage = 'javascript'
      const selectedSdk = 'non-existent-sdk'

      const spySetSelectedSDK = jest.spyOn(manager, 'setSelectedSDK')

      expect(manager.localStorage.uiState.preferredLanguage).toEqual(defaultLocalStorageUiState.preferredLanguage)

      manager.setSelectedLanguage(mockGettingStarted, selectedLanguage, selectedSdk)

      expect(manager.localStorage.uiState.preferredLanguage).toEqual(selectedLanguage)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'SET_SELECTED_LANGUAGE',
        selectedLanguage,
      })
      expect(spySetSelectedSDK).toHaveBeenCalledWith('azure-javascript-sdk')
    })

    it('does nothing if the selectedLanguage does not exist in GettingStarted', () => {
      const {manager, dispatch} = createManager()
      const selectedLanguage = 'non-existent-language'
      const selectedSdk = 'non-existent-sdk'

      const spySetSelectedSDK = jest.spyOn(manager, 'setSelectedSDK')

      expect(manager.localStorage.uiState.preferredLanguage).toEqual(defaultLocalStorageUiState.preferredLanguage)

      manager.setSelectedLanguage(mockGettingStarted, selectedLanguage, selectedSdk)

      expect(manager.localStorage.uiState.preferredLanguage).toEqual(defaultLocalStorageUiState.preferredLanguage)
      expect(dispatch).not.toHaveBeenCalled()
      expect(spySetSelectedSDK).not.toHaveBeenCalled()
    })

    it('does nothing if GettingStarted is empty', () => {
      const {manager, dispatch} = createManager()
      const selectedLanguage = 'non-existent-language'
      const selectedSdk = 'non-existent-sdk'

      const spySetSelectedSDK = jest.spyOn(manager, 'setSelectedSDK')

      expect(manager.localStorage.uiState.preferredLanguage).toEqual(defaultLocalStorageUiState.preferredLanguage)

      manager.setSelectedLanguage({}, selectedLanguage, selectedSdk)

      expect(manager.localStorage.uiState.preferredLanguage).toEqual(defaultLocalStorageUiState.preferredLanguage)
      expect(dispatch).not.toHaveBeenCalled()
      expect(spySetSelectedSDK).not.toHaveBeenCalled()
    })

    it('does nothing if language is blank', () => {
      const {manager, dispatch} = createManager()
      const selectedLanguage = ''
      const selectedSdk = 'non-existent-sdk'

      const spySetSelectedSDK = jest.spyOn(manager, 'setSelectedSDK')

      expect(manager.localStorage.uiState.preferredLanguage).toEqual(defaultLocalStorageUiState.preferredLanguage)

      manager.setSelectedLanguage(mockGettingStarted, selectedLanguage, selectedSdk)

      expect(manager.localStorage.uiState.preferredLanguage).toEqual(defaultLocalStorageUiState.preferredLanguage)
      expect(dispatch).not.toHaveBeenCalled()
      expect(spySetSelectedSDK).not.toHaveBeenCalled()
    })
  })

  describe('setSelectedSDK', () => {
    it('updates local storage and dispatches the action', () => {
      const {manager, dispatch} = createManager()
      const selectedSDK = 'azure-javascript-sdk'

      expect(manager.localStorage.uiState.preferredSdk).toEqual(defaultLocalStorageUiState.preferredSdk)

      manager.setSelectedSDK(selectedSDK)

      expect(manager.localStorage.uiState.preferredSdk).toEqual(selectedSDK)
      expect(dispatch).toHaveBeenCalledTimes(1)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'SET_SELECTED_SDK',
        selectedSDK,
      })
    })
  })

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
        syncInputs,
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

  describe('clearLastPlaceholderMessage', () => {
    it('dispatches the action to clear the last placeholder message', () => {
      const {manager, dispatch} = createManager()
      manager.clearLastPlaceholderMessage(Panel.Main)

      expect(dispatch).toHaveBeenCalledTimes(1)
      expect(dispatch).toHaveBeenCalledWith({
        type: 'CLEAR_LAST_PLACEHOLDER_MESSAGE',
        index: Panel.Main,
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

  describe('resetHistory', () => {
    it('resets the history for the model', () => {
      const {manager, dispatch} = createManager()
      const index = 0

      manager.resetHistory(index)

      expect(dispatch).toHaveBeenCalledTimes(2)
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
          yield response
        }),
      } as unknown as AzureModelClient

      manager.setMessages = jest.fn()
      manager.setIsLoading = jest.fn()
      manager.clearLastPlaceholderMessage = jest.fn()
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
      expect(manager.clearLastPlaceholderMessage).toHaveBeenCalledWith(Panel.Main)
      expect(manager.setChatInput).not.toHaveBeenCalled()
      expect(manager.setChatClosed).not.toHaveBeenCalled()
      expect(manager.setIsLoading).toHaveBeenCalledWith(Panel.Main, false)
    })

    it('sends a message and receives a ModelClientError', async () => {
      const {manager} = createManager()
      const message = 'Hello'
      const userMessage = createUserMessage(message)
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
      manager.clearLastPlaceholderMessage = jest.fn()
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
      expect(manager.clearLastPlaceholderMessage).not.toHaveBeenCalled()
      expect(manager.setChatInput).not.toHaveBeenCalled()
      expect(manager.setChatClosed).not.toHaveBeenCalled()
      expect(manager.setIsLoading).toHaveBeenCalledWith(Panel.Main, false)
    })

    it('sends a message and receives a TooManyRequestsError', async () => {
      const {manager} = createManager()
      const message = 'Hello'
      const userMessage = createUserMessage(message)
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
      manager.clearLastPlaceholderMessage = jest.fn()
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
      expect(manager.clearLastPlaceholderMessage).not.toHaveBeenCalled()
      expect(manager.setChatInput).toHaveBeenCalledWith(Panel.Main, message)
      expect(manager.setChatClosed).not.toHaveBeenCalled()
      expect(manager.setIsLoading).toHaveBeenCalledWith(Panel.Main, false)
    })

    it('sends a message and receives a TokenLimitReachedResponseError', async () => {
      const {manager} = createManager()
      const message = 'Hello'
      const userMessage = createUserMessage(message)
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
      manager.clearLastPlaceholderMessage = jest.fn()
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
      expect(manager.clearLastPlaceholderMessage).not.toHaveBeenCalled()
      expect(manager.setChatInput).not.toHaveBeenCalled()
      expect(manager.setChatClosed).toHaveBeenCalledWith(Panel.Main, true)
      expect(manager.setIsLoading).toHaveBeenCalledWith(Panel.Main, false)
    })

    it('sends a message and receives a generic Error', async () => {
      const {manager} = createManager()
      const message = 'Hello'
      const userMessage = createUserMessage(message)
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
      manager.clearLastPlaceholderMessage = jest.fn()
      manager.setChatInput = jest.fn()
      manager.setChatClosed = jest.fn()
      manager.setIsLoading = jest.fn()

      await manager.sendMessage(Panel.Main, mockModelState, mockModelClient, message, [])

      expect(mockModelClient.sendMessage).toHaveBeenCalledTimes(1)
      expect(manager.setIsLoading).toHaveBeenCalledWith(Panel.Main, true)
      expect(manager.setMessages).toHaveBeenCalledWith(Panel.Main, [
        ...mockModelState.messages,
        {...userMessage, timestamp: expect.any(Date)},
        {...response, message: 'An error occurred. Please try again.', timestamp: expect.any(Date)},
      ])
      expect(manager.clearLastPlaceholderMessage).not.toHaveBeenCalled()
      expect(manager.setChatInput).not.toHaveBeenCalled()
      expect(manager.setChatClosed).not.toHaveBeenCalled()
      expect(manager.setIsLoading).toHaveBeenCalledWith(Panel.Main, false)
    })
  })

  describe('getSideModel', () => {
    it('aborts any previous requests', () => {
      const {manager, abortController} = createManager()
      const abortSpy = jest.spyOn(abortController, 'abort')
      manager.getSideModel('model name', mockModelState)

      expect(abortSpy).toHaveBeenCalled()
    })

    it('returns { success: true } and calls the setModelState method when successful', async () => {
      const {manager} = createManager()
      manager.setModelState = jest.fn()
      const response = await manager.getSideModel('model name', mockModelState)

      expect(manager.setModelState).toHaveBeenCalledTimes(1)
      expect(response).toEqual({success: true})
    })

    it('returns { success: false } and does not call the setModelState method when not successful', async () => {
      const {manager} = createManager()
      manager.setModelState = jest.fn()
      mockVerifiedFetchJSON.mockRejectedValue(new Error('Failed to fetch'))
      const response = await manager.getSideModel('model name', mockModelState)

      expect(manager.setModelState).not.toHaveBeenCalled()
      expect(response).toEqual({success: false})
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
        index: Panel.Side,
      })
    })
  })

  describe('resetParamsAndSystemPrompt', () => {
    it('resets the parameters and system prompt to the defaults of the model provided', () => {
      const {manager} = createManager()
      manager.setParameters = jest.fn()
      manager.setSystemPrompt = jest.fn()

      const modelDetails = {
        catalogData: mockModel,
        modelInputSchema: mockModelInputSchema,
        gettingStarted: mockGettingStarted,
      }
      const modelStateDefaults = getModelStateDefaults(modelDetails)

      manager.resetParamsAndSystemPrompt(Panel.Main, modelDetails)

      expect(manager.setParameters).toHaveBeenCalledTimes(1)
      expect(manager.setParameters).toHaveBeenCalledWith(Panel.Main, modelStateDefaults.parameters)
      expect(manager.setSystemPrompt).toHaveBeenCalledTimes(1)
      expect(manager.setSystemPrompt).toHaveBeenCalledWith(Panel.Main, modelStateDefaults.systemPrompt)
    })
  })
})
