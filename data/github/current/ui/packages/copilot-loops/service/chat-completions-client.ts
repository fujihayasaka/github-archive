import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import type {ChatMessage} from '../types/app'
import {makeCAPIRequest} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {CopilotChatModel, FailedAPIResult} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {generateDefaultModel} from '@github-ui/copilot-chat/utils/models'
import {sendEvent} from '@github-ui/hydro-analytics'

interface ChatCompletionErrorBody {
  error?: {
    message?: string
  }
}

const defaultErrorMessage = 'Unknown error'

export class ChatCompletionsClient {
  readonly #copilotAuthTokenProvider: CopilotAuthTokenProvider
  readonly #apiUrl: string
  readonly #realIp: string

  constructor(apiUrl: string, ssoOrgIds: string[], realIp = '') {
    this.#apiUrl = apiUrl
    this.#copilotAuthTokenProvider = new CopilotAuthTokenProvider(ssoOrgIds)
    this.#realIp = realIp
  }

  async *getChatCompletion(messages: ChatMessage[], model?: string, signal?: AbortSignal): AsyncIterable<string> {
    const defaultModel: CopilotChatModel = generateDefaultModel()
    const selectedModel = model ?? defaultModel.id
    const body = {
      messages,
      model: selectedModel,
      stream: true,
    }

    const token = await this.#copilotAuthTokenProvider.getAuthToken()
    const response = await makeCAPIRequest({
      basePath: this.#apiUrl,
      body,
      path: '/chat/completions',
      method: 'POST',
      streamingResponse: true,
      authToken: token,
      integrationId: this.directConnectConfiguration.integrationID,
      realIp: this.#realIp,
      signal,
    })

    if (!response.ok) {
      const errorResponse = response as FailedAPIResult

      const errorBody = (await errorResponse.response?.text()) ?? defaultErrorMessage
      let errorMessage = errorBody
      try {
        const errorMessageResponseBody = JSON.parse(errorBody) as ChatCompletionErrorBody
        errorMessage = errorMessageResponseBody.error?.message || errorResponse.error
        // eslint-disable-next-line unused-imports/no-unused-vars
      } catch (_: unknown) {
        // Do nothing; the response body was not JSON so the error message will simply be the full request body
      }
      sendEvent('dotcom_chat.error', {type: 'execution', nodeType: 'prompt', mode: 'pipes', errorMessage})
      throw new Error(`Failed to get chat completion: ${errorMessage}`)
    }

    if (signal?.aborted || !response.body) return

    yield* this.#streamChatCompletion(response.body, signal)
  }

  async *#streamChatCompletion(stream: ReadableStream<Uint8Array>, signal?: AbortSignal): AsyncIterable<string> {
    const utf8Decoder = new TextDecoder('utf-8')
    const reader = stream.getReader()
    let partialMessage = ''

    try {
      for (;;) {
        if (signal?.aborted) return

        const {done, value} = await reader.read()
        if (done) break

        // Keep track of partial messages in between stream chunks.
        partialMessage += utf8Decoder.decode(value)

        for (;;) {
          // If we get a DONE chunk, we can exit early.
          if (partialMessage.startsWith('data: [DONE]')) return

          // Find the end of the first message. If there isn't one we need to get the next chunk in the stream.
          const messageEnd = partialMessage.indexOf('\n\n')
          if (messageEnd === -1) break

          const rawMessage = partialMessage.slice(0, messageEnd).replace(/^data:\s+/, '')
          // Empty chunk, nothing to do.
          if (rawMessage === '') {
            // Move to the next potential message in this chunk.
            partialMessage = partialMessage.slice(messageEnd + 2)
            continue
          }

          try {
            const parsedMessage = JSON.parse(rawMessage)
            const content = parsedMessage.choices?.[0]?.delta?.content ?? ''

            if (content) {
              yield content
            }
          } catch {
            // Sometimes we don't get JSON -- don't die for it, just skip
          }

          // Move to the next potential message in this chunk.
          partialMessage = partialMessage.slice(messageEnd + 2)
        }
      }
    } finally {
      reader.releaseLock()
    }
  }

  private get directConnectConfiguration() {
    return process.env.NODE_ENV === 'development'
      ? {integrationID: 'copilot-chat-dev'}
      : {integrationID: 'copilot-chat'}
  }
}
