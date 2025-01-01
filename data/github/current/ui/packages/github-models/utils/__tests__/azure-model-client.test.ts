import {sendEvent} from '@github-ui/hydro-analytics'
import {sendStats} from '@github-ui/stats'
import {AzureModelClient} from '../azure-model-client'
import {Panel} from '../playground-manager'
import {mockFetch} from '@github-ui/mock-fetch'
import {
  PlaygroundChatRequestSent,
  PlaygroundChatRequestStreamingStarted,
  PlaygroundChatRequestStreamingCompleted,
  TokenLimitReachedResponseError,
  TooManyRequestsError,
  ModelClientError,
  PlaygroundChatRateLimited,
} from '../playground-types'
import {mockModel} from '../../routes/playground/__tests__/mocks'
import {authTokenUrl} from '../auth-token'
import {defaultResponseFormat} from '../model-state'
import type {PlaygroundMessage} from '../../types'
import {createUserMessage} from '../message-content-helper'

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
}))
jest.mock('@github-ui/hydro-analytics', () => ({
  sendEvent: jest.fn().mockName('sendEvent'),
}))
jest.mock('@github-ui/stats', () => ({
  sendStats: jest.fn().mockName('sendStats'),
}))
jest.mock('../auth-token', () => ({
  getAuthTokenValue: jest.fn().mockName('getAuthTokenValue'),
}))

const eventData = {registry: mockModel.registry, model: mockModel.name, publisher: mockModel.publisher}

const randomUUID = jest.fn().mockName('randomUUID')

const callSendMessage = ({
  modelClient = new AzureModelClient('http://localhost:3000'),
  panel = Panel.Main,
  model = mockModel,
  messages = [createUserMessage('hello')],
  parameters = {},
  systemPrompt = '',
} = {}): AsyncGenerator<PlaygroundMessage, void, unknown> =>
  modelClient.sendMessage(panel, model, messages, parameters, systemPrompt, defaultResponseFormat)

global.crypto.randomUUID = randomUUID

describe('AzureModelClient', () => {
  const authToken = 'some fine auth token'
  const uuid = 'some-uuid'

  beforeEach(() => {
    randomUUID.mockReturnValue(uuid)
    mockAuthTokenRequest(authToken)
  })

  afterEach(() => {
    localStorage.clear() // wipe out any cached auth tokens so the next test can expect a fresh request
    jest.clearAllMocks()
  })

  describe('sendMessage', () => {
    it('receives a non-streamed reply', async () => {
      mockFetch.fetch.mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({
          choices: [{message: {content: 'Non-streamed response'}}],
        }),
      })

      const res = callSendMessage({
        model: {
          ...mockModel,
          name: 'o1-mini',
        },
      })

      expect.assertions(6)

      for await (const msg of res) {
        expect(msg.role).toEqual('assistant')
        expect(msg.message).toEqual('Non-streamed response')
      }

      expect(sendEvent).toHaveBeenCalledTimes(1)
      expect(sendEvent).toHaveBeenCalledWith(PlaygroundChatRequestSent, {
        ...eventData,
        model: 'o1-mini',
        success: true,
        result_code: 200,
      })

      expect(sendStats).toHaveBeenCalledTimes(1)
      expect(sendStats).toHaveBeenCalledWith({
        incrementKey: 'MODELS_CHAT_REQUEST',
        requestUrl: window.location.href,
      })
    })

    it('receives a streamed reply', async () => {
      mockFetch.fetch.mockResolvedValueOnce({
        ok: true,
        status: 200,
        body: {
          getReader: () => ({
            read: jest
              .fn()
              .mockResolvedValueOnce({
                value: new TextEncoder().encode('data: {"choices": [{"delta": {"content": "Streamed response"}}]}\n\n'),
              })
              .mockResolvedValueOnce({
                done: true,
              }),
          }),
        },
      })

      const res = callSendMessage()

      expect.assertions(8)

      for await (const msg of res) {
        expect(msg.role).toEqual('assistant')
        expect(msg.message).toEqual('Streamed response')
      }

      expect(sendEvent).toHaveBeenCalledTimes(3)
      expect(sendEvent).toHaveBeenCalledWith(PlaygroundChatRequestSent, {
        ...eventData,
        success: true,
        result_code: 200,
      })
      expect(sendEvent).toHaveBeenCalledWith(PlaygroundChatRequestStreamingStarted, eventData)
      expect(sendEvent).toHaveBeenCalledWith(PlaygroundChatRequestStreamingCompleted, eventData)

      expect(sendStats).toHaveBeenCalledTimes(1)
      expect(sendStats).toHaveBeenCalledWith({
        incrementKey: 'MODELS_CHAT_REQUEST',
        requestUrl: window.location.href,
      })
    })

    it('fails to find a reader in a streamed reply', async () => {
      mockFetch.fetch.mockResolvedValueOnce({ok: true})

      const res = callSendMessage()

      const messages = []
      for await (const msg of res) {
        messages.push(msg)
        expect(msg.role).toEqual('assistant')
        expect(msg.message).toEqual('An error occurred. Please try again.')
      }

      expect(messages).toHaveLength(1)
    })

    it('receives reaching token limit error', async () => {
      mockFetch.fetch.mockResolvedValueOnce({
        ok: false,
        status: 413,
      })

      expect.assertions(5)

      try {
        await callSendMessage().next()
      } catch (e) {
        expect(e).toBeInstanceOf(TokenLimitReachedResponseError)
      }

      expect(sendEvent).toHaveBeenCalledTimes(1)
      expect(sendEvent).toHaveBeenCalledWith(PlaygroundChatRequestSent, {
        ...eventData,
        success: false,
        result_code: 413,
      })

      expect(sendStats).toHaveBeenCalledTimes(1)
      expect(sendStats).toHaveBeenCalledWith({
        incrementKey: 'MODELS_CHAT_REQUEST_ERROR',
        requestUrl: window.location.href,
      })
    })

    it('receives rate limiting error', async () => {
      mockFetch.fetch.mockResolvedValueOnce({
        ok: false,
        status: 429,
        headers: {
          get: jest.fn().mockReturnValue('60'),
        },
      })

      expect.assertions(7)

      try {
        await callSendMessage().next()
      } catch (e) {
        expect(e).toBeInstanceOf(TooManyRequestsError)
        expect((e as Error).message).toEqual('Rate limited, please try again in 60 seconds.')
      }

      expect(sendEvent).toHaveBeenCalledTimes(2)
      expect(sendEvent).toHaveBeenCalledWith(PlaygroundChatRequestSent, {
        ...eventData,
        success: false,
        result_code: 429,
      })
      expect(sendEvent).toHaveBeenCalledWith(PlaygroundChatRateLimited, {
        ...eventData,
        rate_limit_type: '60',
      })

      expect(sendStats).toHaveBeenCalledTimes(1)
      expect(sendStats).toHaveBeenCalledWith({
        incrementKey: 'MODELS_CHAT_REQUEST_ERROR',
        requestUrl: window.location.href,
      })
    })

    it('receives a generic error', async () => {
      mockFetch.fetch.mockResolvedValueOnce({
        ok: false,
        status: 500,
      })

      expect.assertions(6)

      try {
        await callSendMessage().next()
      } catch (e) {
        expect(e).toBeInstanceOf(ModelClientError)
        if (e instanceof ModelClientError) {
          expect(e.message).toEqual('An error occurred while processing your request.')
        }
      }

      expect(sendEvent).toHaveBeenCalledTimes(1)
      expect(sendEvent).toHaveBeenCalledWith(PlaygroundChatRequestSent, {
        ...eventData,
        success: false,
        result_code: 500,
      })

      expect(sendStats).toHaveBeenCalledTimes(1)
      expect(sendStats).toHaveBeenCalledWith({
        incrementKey: 'MODELS_CHAT_REQUEST_ERROR',
        requestUrl: window.location.href,
      })
    })

    it('receives a generic error with a json message', async () => {
      mockFetch.fetch.mockResolvedValueOnce({
        ok: false,
        status: 500,
        json: async () => ({
          error: {
            message: 'A json error message',
          },
        }),
      })

      expect.assertions(6)

      try {
        await callSendMessage().next()
      } catch (e) {
        expect(e).toBeInstanceOf(ModelClientError)
        if (e instanceof ModelClientError) {
          expect(e.message).toEqual('A json error message')
        }
      }

      expect(sendEvent).toHaveBeenCalledTimes(1)
      expect(sendEvent).toHaveBeenCalledWith(PlaygroundChatRequestSent, {
        ...eventData,
        success: false,
        result_code: 500,
      })

      expect(sendStats).toHaveBeenCalledTimes(1)
      expect(sendStats).toHaveBeenCalledWith({
        incrementKey: 'MODELS_CHAT_REQUEST_ERROR',
        requestUrl: window.location.href,
      })
    })
  })
})

function mockAuthTokenRequest(token: string) {
  mockVerifiedFetchJSON.mockImplementation(path => {
    if (path === authTokenUrl) {
      const futureExpirationTime = new Date(Date.now() + 16000)
      return {ok: true, json: () => ({token, expiration: futureExpirationTime.toISOString()})}
    }
    throw new Error(`Unexpected verifiedFetchJSON call: ${path}`)
  })
}
