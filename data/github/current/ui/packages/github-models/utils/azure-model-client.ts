import {sendEvent} from '@github-ui/hydro-analytics'
import safeStorage from '@github-ui/safe-storage'
import {sendStats} from '@github-ui/stats'
import type {
  AnalyticalModel,
  MessageableModel,
  ModelClient,
  ModelClientSendMessageResponse,
  PlaygroundAPIMessage,
  PlaygroundMessage,
  PlaygroundRequestParameters,
  PlaygroundResponseFormat,
  TextInputs,
  TokenUsageInfo,
  ToolCall,
} from '../types'
import authToken from './auth-token'
import {createAssistantMessage, createToolMessage} from './message-content-helper'
import {MessageStreamer} from './message-streamer'
import {supportsJsonSchemaStructuredOutput, supportsStreamingOptions} from './model-capability'
import {tokenUsageFromChunk, tokenUsageFromResponse} from './model-usage'
import {
  CompletionTokensLimitReachedResponseError,
  ModelClientError,
  PlaygroundChatRateLimited,
  PlaygroundChatRequestSent,
  PlaygroundChatRequestStreamingCompleted,
  PlaygroundChatRequestStreamingStarted,
  TimeoutError,
  TokenLimitReachedResponseError,
  TooManyRequestsError,
} from './playground-types'
import {searchDocuments} from './rag-index-manager'
export const userAgent = 'github-models-playground'

const MODELS_WITH_THINK_TAG = [
  'DeepSeek-R1',
  'DeepSeek-R1-0528',
  'MAI-DS-R1',
  'Phi-4-reasoning',
  'Phi-4-mini-reasoning',
]

export class AzureModelClient implements ModelClient {
  url: string
  timeoutInMs: number = 300000 // 5 mins
  chunkTimeoutInMs: number = 10000 // 10s
  provider: string = 'azureml'
  // Has to be an object as in comparison mode a Panel can trigger messages for another Panel
  messageStreamers: {[key: string]: MessageStreamer} = {}

  constructor(url: string) {
    this.url = url
  }

  async sendNonStreamingMessage(
    model: AnalyticalModel & {original_name: string; publisherSlug: string},
    messages: PlaygroundMessage[],
    parameters: PlaygroundRequestParameters,
    systemPrompt: string | null,
    responseFormat: PlaygroundResponseFormat,
    jsonSchema?: string,
    abortSignal?: AbortSignal,
  ): Promise<ModelClientSendMessageResponse> {
    const res = await this.makeRequest(model, messages, parameters, systemPrompt, responseFormat, jsonSchema, {
      abortSignal,
      stream: false,
    })

    // If the response is not ok, we throw an error
    if (!res.ok) throw await this.throwError(res, model)

    return this.getNonStreamingResponse(res)
  }

  async *sendMessage(
    panel: number,
    model: MessageableModel,
    messages: PlaygroundMessage[],
    parameters: PlaygroundRequestParameters,
    systemPrompt: string | null,
    responseFormat: PlaygroundResponseFormat,
    jsonSchema?: string,
  ): AsyncGenerator<ModelClientSendMessageResponse, TokenUsageInfo | undefined, unknown> {
    const controller = new AbortController()

    const options = {abortSignal: controller.signal}

    const res = await this.makeRequest(model, messages, parameters, systemPrompt, responseFormat, jsonSchema, options)

    this.emitChatRequestSent(res, model, !!parameters.tools)

    // If the response is not ok, we throw an error
    if (!res.ok) throw await this.throwError(res, model)

    // If the model does not support streaming we return the response here
    if (!model.capabilities?.streaming) {
      const response = await this.getNonStreamingResponse(res)
      yield response
      return
    }

    this.emitStreamingStarted(model)
    let fullMessage = ''

    const reader = res.body?.getReader()
    if (!reader) {
      const message = createAssistantMessage('An error occurred. Please try again.')
      yield {message}
      return
    }

    // Stop any existing streaming for this panel
    this.stopStreamingMessages(panel)
    this.messageStreamers[panel] = new MessageStreamer(reader, this.chunkTimeoutInMs, controller)

    // Keep track of tool calls, since the arguments are split up
    // in multiple chunks.
    const toolCalls: ToolCall[] = []

    // Models return tokenUsage at different chunks. This is a way to make sure we can capture the token usage
    // and return it together with the last chunk.
    let tokenUsage: TokenUsageInfo = {inputTokens: 0, outputTokens: 0}

    for await (const chunk of this.messageStreamers[panel].stream()) {
      if (chunk.usage) {
        tokenUsage = tokenUsageFromChunk(chunk)
      }
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
              })
            } catch (err: Error | unknown) {
              functionResponse = `Error searching documents: ${err}`
            }
          }
        }

        messages.push(createToolMessage(functionResponse, toolToCall.id))

        for await (const msg of this.sendMessage(
          panel,
          model,
          messages,
          parameters,
          systemPrompt,
          responseFormat,
          jsonSchema,
        )) {
          yield msg
        }
      }

      const reachedMaxTokens = chunk.choices[0]?.finish_reason === 'length'

      if (!chunk.choices[0]?.delta?.content && !reachedMaxTokens) {
        continue
      }
      fullMessage += chunk.choices[0]?.delta?.content

      yield {
        message: createAssistantMessage(fullMessage),
        tokenUsage,
        reachedMaxTokens,
      }
    }

    this.emitStreamingCompleted(model)
    return tokenUsage
  }

  stopStreamingMessages = (position: number) => {
    const messageStreamer = this.messageStreamers[position]
    messageStreamer?.stop()
  }

  private async throwError(res: Response, model: AnalyticalModel): Promise<ModelClientError> {
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
    model: MessageableModel,
    messages: PlaygroundMessage[],
    parameters: PlaygroundRequestParameters,
    systemPrompt: string | null,
    responseFormat: PlaygroundResponseFormat | null,
    jsonSchema?: string,
    options?: {
      /** Optional, custom abort signal */
      abortSignal?: AbortSignal

      /** Optional, override the stream behavior */
      stream?: boolean
    },
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
      // The o1 model requires its own role name for system prompts
      const systemPromptRoleName = model.name === 'o1' ? 'developer' : 'system'
      newMessages.push({role: systemPromptRoleName, content: systemPrompt})
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
      model?: string
      publisher?: string
      provider?: string
      messages: PlaygroundAPIMessage[]
      response_format?: {type: PlaygroundResponseFormat; json_schema?: string}
      stream_options?: object
    } = {
      ...parameters,
      messages: newMessages,
    }
    const isJsonSchemaRequest =
      responseFormat === 'json_schema' && jsonSchema && supportsJsonSchemaStructuredOutput(model)

    // Don't include response format or json schema if model doesn't support it
    // Don't include response format at all if it's text
    if (isJsonSchemaRequest) {
      body.response_format = {type: responseFormat, json_schema: JSON.parse(jsonSchema)}
    } else if (responseFormat && model.capabilities?.structuredOutput) {
      body.response_format = {type: responseFormat}
    }

    // Models includes CoT content in the messages inside <think></think> tags.
    // To avoid always sending an expensive message back, we need to parse that content out here (including the
    // case where a user has aborted the last message early so we only have the opening <think> tag):
    if (MODELS_WITH_THINK_TAG.includes(model.name)) {
      body.messages = body.messages.map(message => {
        if (message.role === 'assistant') {
          // if message.content is a string, parse out the <think> tags
          if (typeof message.content === 'string') {
            // Remove content inside <think> tags including the case with only opening <think> tag
            const thinkTagRegex = /<think>(.*?)<\/think>/gs
            const openThinkTagRegex = /<think>.*$/gs

            message.content = message.content.replace(thinkTagRegex, '').replace(openThinkTagRegex, '').trim()
          }
          return message
        } else {
          return message
        }
      })
    }

    // o1 models do not support streaming
    if (model.capabilities?.streaming) {
      body.stream = true
    }

    if (options?.stream !== undefined) {
      body.stream = options.stream
    }

    if (supportsStreamingOptions(model) && body.stream) {
      body.stream_options = {include_usage: true}
    }

    let abortSignal: AbortSignal | undefined = options?.abortSignal
    if (!abortSignal) {
      const controller = new AbortController()
      setTimeout(() => controller.abort(new TimeoutError('Sorry, this is taking longer than usual.')), this.timeoutInMs)
      abortSignal = controller.signal
    }

    // The gateway expects/requires a model to be sent in a body param.
    body.provider = this.provider
    body.model = `${model.publisherSlug.toLowerCase()}/${model.original_name.toLowerCase()}`

    return fetch(this.url, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
      signal: abortSignal,
    })
  }

  private async getNonStreamingResponse(res: Response): Promise<ModelClientSendMessageResponse> {
    const {choices = [], usage = {}} = await res.json()
    const messageContent = choices[0]?.message?.content || ''

    // some models like o1 don't send an error code when they hit their response limit
    if (messageContent === '' && choices[0].finish_reason === 'length') {
      throw new CompletionTokensLimitReachedResponseError()
    }

    return {
      message: createAssistantMessage(messageContent),
      tokenUsage: tokenUsageFromResponse(usage),
    }
  }

  private localStorage = safeStorage('localStorage', {
    throwQuotaErrorsOnSet: false,
    ttl: 1000 * 60 * 60 * 24,
  })

  private emitChatRequestSent(res: Response, model: AnalyticalModel, usedRag: boolean) {
    sendEvent(PlaygroundChatRequestSent, {
      registry: model.registry,
      model: model.name,
      publisher: model.publisher,
      success: res.ok,
      result_code: res.status,
      used_rag: usedRag,
    })

    if (res.ok) {
      sendStats({incrementKey: 'MODELS_CHAT_REQUEST', requestUrl: window.location.href})
    } else {
      sendStats({incrementKey: 'MODELS_CHAT_REQUEST_ERROR', requestUrl: window.location.href})
    }
  }

  private emitRateLimitedEvent(res: Response, model: AnalyticalModel) {
    sendEvent(PlaygroundChatRateLimited, {
      registry: model.registry,
      model: model.name,
      publisher: model.publisher,
      rate_limit_type: res.headers.get('X-RateLimit-Type'),
    })
  }

  private emitStreamingStarted(model: AnalyticalModel) {
    sendEvent(PlaygroundChatRequestStreamingStarted, {
      registry: model.registry,
      model: model.name,
      publisher: model.publisher,
    })
  }

  private emitStreamingCompleted(model: AnalyticalModel) {
    sendEvent(PlaygroundChatRequestStreamingCompleted, {
      registry: model.registry,
      model: model.name,
      publisher: model.publisher,
    })
  }
}
