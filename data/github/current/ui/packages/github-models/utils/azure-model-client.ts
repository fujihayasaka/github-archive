import safeStorage from '@github-ui/safe-storage'
import authToken from './auth-token'
import type {
  PlaygroundAPIMessage,
  PlaygroundMessage,
  PlaygroundRequestParameters,
  PlaygroundResponseFormat,
  TextInputs,
  ToolCall,
  ModelClient,
} from '../types'
import type {Model} from '@github-ui/marketplace-common'
import {MessageStreamer} from './message-streamer'
import {
  TooManyRequestsError,
  PlaygroundChatRequestSent,
  PlaygroundChatRequestStreamingStarted,
  PlaygroundChatRequestStreamingCompleted,
  PlaygroundChatRateLimited,
  TokenLimitReachedResponseError,
  TimeoutError,
  ModelClientError,
} from './playground-types'
import {sendEvent} from '@github-ui/hydro-analytics'
import {sendStats} from '@github-ui/stats'
import {searchDocuments} from './rag-index-manager'
import {createAssistantMessage, createToolMessage} from './message-content-helper'
import {supportsStreaming} from './stream-utils'
export const userAgent = 'github-models-playground'

export class AzureModelClient implements ModelClient {
  url: string
  timeoutInMs: number = 120000 // 2 mins
  // Has to be an object as in comparison mode a Panel can trigger messages for another Panel
  messageStreamers: {[key: string]: MessageStreamer} = {}

  constructor(url: string) {
    this.url = url
  }

  async *sendMessage(
    panel: number,
    model: Model,
    messages: PlaygroundMessage[],
    parameters: PlaygroundRequestParameters,
    systemPrompt: string | null,
    responseFormat: PlaygroundResponseFormat,
  ): AsyncGenerator<PlaygroundMessage, void, unknown> {
    const res = await this.makeRequest(model, messages, parameters, systemPrompt, responseFormat)

    this.emitChatRequestSent(res, model)

    // If the response is not ok, we throw an error
    if (!res.ok) throw await this.throwError(res, model)

    // If the model does not support streaming we return the response here
    if (!supportsStreaming(model)) {
      yield await this.getNonStreamingMessages(res)
      return
    }

    this.emitStreamingStarted(model)
    let fullMessage = ''

    const reader = res.body?.getReader()
    if (!reader) {
      yield createAssistantMessage('An error occurred. Please try again.')
      return
    }

    // Stop any existing streaming for this panel
    this.stopStreamingMessages(panel)
    this.messageStreamers[panel] = new MessageStreamer(reader)

    // Keep track of tool calls, since the arguments are split up
    // in multiple chunks.
    const toolCalls: ToolCall[] = []

    for await (const chunk of this.messageStreamers[panel].stream()) {
      if (chunk.choices.length === 0) {
        continue
      }

      // Loop through each tool call in this chunk and
      // merge the arguments into the tracking array.
      for (const toolCall of chunk.choices[0]?.delta?.tool_calls ?? []) {
        // The first chunk for a tool call will have the name,
        // subsequent chunks will have the arguments.
        if (toolCall.function.name) {
          toolCalls.push(toolCall)
          continue
        }
        // toolCall.index can be 0, so we need to check if the key exists
        if ('index' in toolCall) {
          ;(toolCalls[toolCall.index] as ToolCall).function.arguments += toolCall.function.arguments
          continue
        }
      }

      if (chunk.choices[0]?.finish_reason === 'tool_calls') {
        const toolToCall = toolCalls[chunk.choices[0]?.index] as ToolCall

        let functionResponse = ''
        switch (toolToCall?.function.name) {
          case 'search_documents': {
            const searchArgs = JSON.parse(toolToCall.function.arguments)
            messages.push(
              createAssistantMessage([
                {type: 'tool_calls', tool_calls: [toolToCall]},
                {type: 'text', text: `Searching documents in index for "${searchArgs.query}"...`},
              ]),
            )
            try {
              functionResponse = await searchDocuments({
                query: searchArgs.query,
                endpoint: this.localStorage.getItem('ragIndexEndpoint')!,
                apiKey: this.localStorage.getItem('ragIndexAPIKey')!, // (await this.getAuthToken()).token
              })
            } catch (err: Error | unknown) {
              functionResponse = `Error searching documents: ${err}`
            }
          }
        }

        messages.push(createToolMessage(functionResponse, toolToCall.id))

        for await (const msg of this.sendMessage(panel, model, messages, parameters, systemPrompt, responseFormat)) {
          yield msg
        }
      }

      if (!chunk.choices[0]?.delta?.content) {
        continue
      }
      fullMessage += chunk.choices[0]?.delta?.content

      yield createAssistantMessage(fullMessage)
    }

    this.emitStreamingCompleted(model)
  }

  stopStreamingMessages = (position: number) => {
    const messageStreamer = this.messageStreamers[position]
    messageStreamer?.stop()
  }

  private async throwError(res: Response, model: Model): Promise<ModelClientError> {
    switch (res.status) {
      case 413:
        return new TokenLimitReachedResponseError()
      case 429: {
        this.emitRateLimitedEvent(res, model)
        return new TooManyRequestsError(res.headers.get('retry-after'))
      }
    }

    // No special handling, lets check if the response is JSON and has more info
    const genericError = 'An error occurred while processing your request.'
    try {
      const json = await res.json()
      return new ModelClientError(json?.error?.message || genericError)
    } catch {
      return new ModelClientError(genericError)
    }
  }

  private async makeRequest(
    model: Model,
    messages: PlaygroundMessage[],
    parameters: PlaygroundRequestParameters,
    systemPrompt: string | null,
    responseFormat: PlaygroundResponseFormat | null,
  ) {
    const uuid = globalThis.crypto?.randomUUID?.() || null
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'x-ms-model-mesh-model-name': model.original_name.toLowerCase(),
      'x-ms-useragent': userAgent,
      'x-ms-user-agent': userAgent, // send both to accommodate various Azure consumers
      Authorization: await authToken.getAuthTokenValue(),
    }

    if (uuid) {
      headers['x-ms-client-request-id'] = uuid
    }

    const newMessages: PlaygroundAPIMessage[] = []
    if (systemPrompt) {
      newMessages.push({role: 'system', content: systemPrompt})
    }

    const existingMessagesAsPayload: PlaygroundAPIMessage[] = messages
      // Dont send error messages back to the API
      .filter(m => m.role !== 'error')
      .map(m => {
        // If the message is an array with a text type, convert it
        // to an assistant message where content is the text.
        if (Array.isArray(m.message) && m.message[0]!.type === 'tool_calls') {
          return {
            role: m.role,
            content: (m.message[1] as TextInputs).text,
            tool_calls: m.message[0]!.tool_calls,
          }
        }
        // If it's a tool message, ensure the `tool_call_id` is attached.
        if (m.role === 'tool') {
          return {
            role: m.role,
            content: m.message,
            tool_call_id: m.tool_call_id,
          }
        }
        return {role: m.role, content: m.message}
      })

    for (const m of existingMessagesAsPayload) {
      if (typeof m.content === 'string') {
        if (m.content.trim() !== '') {
          newMessages.push(m)
        }
      } else {
        newMessages.push(m)
      }
    }

    const body: {
      stream?: boolean
      messages: PlaygroundAPIMessage[]
      response_format: {type: PlaygroundResponseFormat}
    } = {
      ...parameters,
      messages: newMessages,
      response_format: {type: responseFormat || 'text'},
    }

    // o1 models do not support streaming
    if (supportsStreaming(model)) {
      body.stream = true
    }

    const controller = new AbortController()
    setTimeout(() => controller.abort(new TimeoutError('Sorry, this is taking longer than usual.')), this.timeoutInMs)
    return fetch(this.url, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
      signal: controller.signal,
    })
  }

  private async getNonStreamingMessages(res: Response): Promise<PlaygroundMessage> {
    const {choices = []} = await res.json()
    return createAssistantMessage(choices[0]?.message?.content || '')
  }

  private localStorage = safeStorage('localStorage', {
    throwQuotaErrorsOnSet: false,
    ttl: 1000 * 60 * 60 * 24,
  })

  private emitChatRequestSent(res: Response, model: Model) {
    sendEvent(PlaygroundChatRequestSent, {
      registry: model.registry,
      model: model.name,
      publisher: model.publisher,
      success: res.ok,
      result_code: res.status,
    })

    if (res.ok) {
      sendStats({incrementKey: 'MODELS_CHAT_REQUEST', requestUrl: window.location.href})
    } else {
      sendStats({incrementKey: 'MODELS_CHAT_REQUEST_ERROR', requestUrl: window.location.href})
    }
  }

  private emitRateLimitedEvent(res: Response, model: Model) {
    sendEvent(PlaygroundChatRateLimited, {
      registry: model.registry,
      model: model.name,
      publisher: model.publisher,
      rate_limit_type: res.headers.get('X-RateLimit-Type'),
    })
  }

  private emitStreamingStarted(model: Model) {
    sendEvent(PlaygroundChatRequestStreamingStarted, {
      registry: model.registry,
      model: model.name,
      publisher: model.publisher,
    })
  }

  private emitStreamingCompleted(model: Model) {
    sendEvent(PlaygroundChatRequestStreamingCompleted, {
      registry: model.registry,
      model: model.name,
      publisher: model.publisher,
    })
  }
}
