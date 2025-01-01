import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import type {ChatMessage} from '../types/app'
import {makeCAPIRequest} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {parseResponseStream} from '../utils/stream-helpers'
import type {FailedAPIResult} from '@github-ui/copilot-chat/utils/copilot-chat-types'

export class ChatCompletionsClient {
  readonly #copilotAuthTokenProvider: CopilotAuthTokenProvider
  readonly #apiUrl: string
  readonly #realIp: string

  constructor(apiUrl: string, ssoOrgIds: string[], realIp = '') {
    this.#apiUrl = apiUrl
    this.#copilotAuthTokenProvider = new CopilotAuthTokenProvider(ssoOrgIds)
    this.#realIp = realIp
  }

  async getChatCompletion(
    messages: ChatMessage[],
    onPartialResult?: (result: string) => void,
    signal?: AbortSignal,
  ): Promise<string> {
    const body = {
      messages,
      model: 'gpt-4',
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

    if (!response.ok) throw new Error(`Failed to get chat completion: ${await (response as FailedAPIResult).error}`)

    if (signal?.aborted || !response.body) return ''

    const parsedResponse = await parseResponseStream(response.body, onPartialResult)
    return parsedResponse ?? ''
  }

  private get directConnectConfiguration() {
    return process.env.NODE_ENV === 'development'
      ? {integrationID: 'copilot-chat-dev'}
      : {integrationID: 'copilot-chat'}
  }
}
