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
import {createUserMessage} from '../message-content-helper'
import type {ModelClientSendMessageResponse, TokenUsageInfo} from '../../types'
import {isFeatureEnabled} from '@github-ui/feature-flags'

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
jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest.fn(),
}))

const mockedIsFeatureEnabled = jest.mocked(isFeatureEnabled)

const eventData = {registry: mockModel.registry, model: mockModel.name, publisher: mockModel.publisher}

const randomUUID = jest.fn().mockName('randomUUID')

const baseUrl = 'http://localhost:3000'
const jsonSchemaUrl = `${baseUrl}?api-version=2024-08-01-preview`

const callSendMessage = ({
  modelClient = new AzureModelClient(baseUrl),
  panel = Panel.Main,
  model = mockModel,
  messages = [createUserMessage('hello')],
  parameters = {},
  systemPrompt = '',
  responseFormat = defaultResponseFormat,
  jsonSchema = '',
} = {}): AsyncGenerator<ModelClientSendMessageResponse, TokenUsageInfo | undefined, unknown> =>
  modelClient.sendMessage(panel, model, messages, parameters, systemPrompt, responseFormat, jsonSchema)

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

      for await (const msgRes of res) {
        const msg = msgRes.message
        expect(msg.role).toEqual('assistant')
        expect(msg.message).toEqual('Non-streamed response')
      }

      expect(sendEvent).toHaveBeenCalledTimes(1)
      expect(sendEvent).toHaveBeenCalledWith(PlaygroundChatRequestSent, {
        ...eventData,
        model: 'o1-mini',
        success: true,
        result_code: 200,
        used_rag: false,
      })

      expect(sendStats).toHaveBeenCalledTimes(1)
      expect(sendStats).toHaveBeenCalledWith({
        incrementKey: 'MODELS_CHAT_REQUEST',
        requestUrl: window.location.href,
      })
    })

    it('receives a streamed reply', async () => {
      mockedIsFeatureEnabled.mockImplementation(_feature => {
        return false
      })

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

      for await (const msgRes of res) {
        const msg = msgRes.message
        expect(msg.role).toEqual('assistant')
        expect(msg.message).toEqual('Streamed response')
      }

      expect(sendEvent).toHaveBeenCalledTimes(3)
      expect(sendEvent).toHaveBeenCalledWith(PlaygroundChatRequestSent, {
        ...eventData,
        success: true,
        result_code: 200,
        used_rag: false,
      })
      expect(sendEvent).toHaveBeenCalledWith(PlaygroundChatRequestStreamingStarted, eventData)
      expect(sendEvent).toHaveBeenCalledWith(PlaygroundChatRequestStreamingCompleted, eventData)

      expect(sendStats).toHaveBeenCalledTimes(1)
      expect(sendStats).toHaveBeenCalledWith({
        incrementKey: 'MODELS_CHAT_REQUEST',
        requestUrl: window.location.href,
      })
    })

    it('receives a streamed reply with per-chunk timeout disabled', async () => {
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

      for await (const msgRes of res) {
        const msg = msgRes.message
        expect(msg.role).toEqual('assistant')
        expect(msg.message).toEqual('Streamed response')
      }

      expect(sendEvent).toHaveBeenCalledTimes(3)
      expect(sendEvent).toHaveBeenCalledWith(PlaygroundChatRequestSent, {
        ...eventData,
        success: true,
        result_code: 200,
        used_rag: false,
      })
      expect(sendEvent).toHaveBeenCalledWith(PlaygroundChatRequestStreamingStarted, eventData)
      expect(sendEvent).toHaveBeenCalledWith(PlaygroundChatRequestStreamingCompleted, eventData)

      expect(sendStats).toHaveBeenCalledTimes(1)
      expect(sendStats).toHaveBeenCalledWith({
        incrementKey: 'MODELS_CHAT_REQUEST',
        requestUrl: window.location.href,
      })
    })

    it('sends publisher and provider in request body when feature flag is enabled', async () => {
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

      mockedIsFeatureEnabled.mockImplementation(feature => {
        if (feature === 'github_models_gateway') {
          return true
        }
        return false
      })

      const res = callSendMessage()

      for await (const msgRes of res) {
        const msg = msgRes.message
        expect(msg.role).toEqual('assistant')
        expect(msg.message).toEqual('Streamed response')
      }

      expect(mockFetch.fetch).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          body: expect.stringContaining(`"publisher":"${mockModel.publisher.toLowerCase()}","provider":"azureml"`),
        }),
      )
    })

    it('does not send publisher and provider in request body when feature flag is disabled', async () => {
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

      mockedIsFeatureEnabled.mockImplementation(feature => {
        if (feature === 'github_models_gateway') {
          return false
        }
        return false
      })

      const res = callSendMessage()

      for await (const msgRes of res) {
        const msg = msgRes.message
        expect(msg.role).toEqual('assistant')
        expect(msg.message).toEqual('Streamed response')
      }

      expect(mockFetch.fetch).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          body: expect.not.stringContaining(`"publisher":"${mockModel.publisher.toLowerCase()}","provider":"azureml"`),
        }),
      )
    })

    it('send a used_rag=true event when rag is being used', async () => {
      mockedIsFeatureEnabled.mockImplementation(_feature => {
        return false
      })

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

      const res = callSendMessage({
        parameters: {
          tools: [
            {
              type: 'function',
              function: {
                name: 'search_documents',
                description: 'Search documents matching a query given as a series of keywords.',
                parameters: {
                  type: 'object',
                  properties: {
                    query: {
                      type: 'string',
                      description: 'a series of keywords to use as query to search documents',
                    },
                  },
                  required: ['query'],
                },
              },
            },
          ],
        },
      })

      expect.assertions(8)

      for await (const msgRes of res) {
        const msg = msgRes.message
        expect(msg.role).toEqual('assistant')
        expect(msg.message).toEqual('Streamed response')
      }

      expect(sendEvent).toHaveBeenCalledTimes(3)
      expect(sendEvent).toHaveBeenCalledWith(PlaygroundChatRequestSent, {
        ...eventData,
        success: true,
        result_code: 200,
        used_rag: true,
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
      for await (const msgRes of res) {
        const msg = msgRes.message
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
        used_rag: false,
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
        used_rag: false,
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
        used_rag: false,
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
        used_rag: false,
      })

      expect(sendStats).toHaveBeenCalledTimes(1)
      expect(sendStats).toHaveBeenCalledWith({
        incrementKey: 'MODELS_CHAT_REQUEST_ERROR',
        requestUrl: window.location.href,
      })
    })

    it('routes a jsonSchema request to the correct endpoint', async () => {
      const jsonSchema = '{"type": "object"}'
      const jsonSchemaModelName = 'gpt-4o'
      eventData.model = jsonSchemaModelName

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

      // Only gpt-4o supports JSON Schema structured outputs for now
      const res = callSendMessage({
        model: {
          ...mockModel,
          name: jsonSchemaModelName,
        },
        responseFormat: 'json_schema',
        jsonSchema,
      })
      await res.next()

      expect(mockFetch.fetch).toHaveBeenCalledWith(jsonSchemaUrl, expect.any(Object))
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
