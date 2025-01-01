import safeStorage from '@github-ui/safe-storage'
import {PROMPT_EVALS_LOCAL_STORAGE_KEY} from '../../../utils/prompt-evals-local-storage'
import {mockModel, mockModelState} from '../../playground/__tests__/mocks'
import {PromptEvalsManager} from '../prompt-evals-manager'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {createAssistantMessage, createUserMessage} from '../../../utils/message-content-helper'
import type {AzureModelClient} from '../../../utils/azure-model-client'
import type {MessagePair} from '../../../types'

const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
}))

const safeLocalStorage = safeStorage('localStorage')

const createManager = () => {
  const abortController = new AbortController()
  const dispatch = jest.fn()
  const manager = new PromptEvalsManager(dispatch)
  mockVerifiedFetchJSON.mockResolvedValue({
    ok: true,
    statusText: 'OK',
    json: async () => mockModel,
  })
  return {abortController, dispatch, manager}
}

afterEach(() => {
  safeLocalStorage.removeItem(PROMPT_EVALS_LOCAL_STORAGE_KEY)
})

afterAll(() => {
  jest.clearAllMocks()
})

describe('PromptEvalsManager', () => {
  describe('evalsClearUserSystemPromptAndVariables', () => {
    it('clears the prompts and variables', () => {
      const {manager} = createManager()
      manager.setVariables = jest.fn()
      manager.evalsClearUserSystemPrompt = jest.fn()

      manager.evalsClearUserSystemPromptAndVariables()
      expect(manager.setVariables).toHaveBeenCalledTimes(1)
      expect(manager.setVariables).toHaveBeenCalledWith({})
      expect(manager.evalsClearUserSystemPrompt).toHaveBeenCalledTimes(1)
    })
  })

  describe('sendMessage', () => {
    it('sends a message and receives a valid response', async () => {
      const {manager} = createManager()
      const message = 'Hello'
      const userMessage = createUserMessage(message)
      const response = createUserMessage('Hi, how can I help you today?')
      const mockClient = {
        sendMessage: jest.fn(async function* () {
          yield {message: response}
        }),
      } as unknown as AzureModelClient

      manager.setMessages = jest.fn()
      manager.setIsLoading = jest.fn()

      await manager.sendMessage(mockModelState, mockClient, '', message)

      expect(mockClient.sendMessage).toHaveBeenCalledTimes(1)
      expect(manager.setIsLoading).toHaveBeenCalledTimes(2)
      expect(manager.setIsLoading).toHaveBeenCalledWith(true)
      expect(manager.setMessages).toHaveBeenCalledTimes(2)
      expect(manager.setMessages).toHaveBeenCalledWith([
        ...mockModelState.messages,
        {...userMessage, timestamp: expect.any(Date)},
        {...response, timestamp: expect.any(Date)},
      ])
      expect(manager.setIsLoading).toHaveBeenCalledWith(false)
    })
  })

  it('sends message pair along with the message if present', async () => {
    const {manager} = createManager()
    const initialUserMessage = 'Hello'
    const initialMessage = createUserMessage(initialUserMessage)
    const messagePairs: MessagePair[] = [
      {
        assistant: 'Hi, how can I help you today?',
        user: 'I need help with my computer',
      },
    ]
    const messagePairAssistant = createAssistantMessage('Hi, how can I help you today?')
    const messagePairUser = createUserMessage('I need help with my computer')
    const assistantFinalResponse = createUserMessage('I can help with that.')

    const mockClient = {
      sendMessage: jest.fn(async function* () {
        yield {message: assistantFinalResponse}
      }),
    } as unknown as AzureModelClient

    manager.setMessages = jest.fn()
    manager.setIsLoading = jest.fn()

    await manager.sendMessage(mockModelState, mockClient, '', initialUserMessage, [], messagePairs)

    expect(mockClient.sendMessage).toHaveBeenCalledTimes(1)
    expect(manager.setIsLoading).toHaveBeenCalledTimes(2)
    expect(manager.setIsLoading).toHaveBeenCalledWith(true)
    expect(manager.setMessages).toHaveBeenCalledTimes(2)
    expect(manager.setMessages).toHaveBeenCalledWith([
      ...mockModelState.messages,
      {...initialMessage, timestamp: expect.any(Date)},
      {...messagePairAssistant, timestamp: expect.any(Date)},
      {...messagePairUser, timestamp: expect.any(Date)},
      {...assistantFinalResponse, timestamp: expect.any(Date)},
    ])
  })
})
