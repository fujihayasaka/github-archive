import {makeCAPIRequest} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import type {DashboardIssue} from '../types'
import {buildMessages} from './issue-summary-message-builder'

export class CopilotAPIClient {
  readonly #copilotAuthTokenProvider: CopilotAuthTokenProvider

  constructor() {
    this.#copilotAuthTokenProvider = new CopilotAuthTokenProvider([])
  }

  async getIssueSummariesByTitle(
    issues: DashboardIssue[],
    prompt: string,
    temperature: number,
  ): Promise<Map<string, string>> {
    if (issues.length === 0) {
      return new Map()
    }

    const messages = buildMessages(issues, prompt)
    const body = {
      messages,
      model: 'gpt-4',
      stream: false,
      temperature,
    }
    const token = await this.#copilotAuthTokenProvider.getAuthToken()
    const response = await makeCAPIRequest({
      basePath: 'https://api.githubcopilot.com',
      body,
      path: '/chat/completions',
      method: 'POST',
      streamingResponse: false,
      authToken: token,
      integrationId: this.getIntegrationID(),
    })

    if (response.ok) {
      return this.parseResponse(response)
    }

    return new Map()
  }

  private async parseResponse(response: Response): Promise<Map<string, string>> {
    const data = await response.json()
    const content = data.choices[0].message.content
    const obj = JSON.parse(this.removeMarkdown(content))
    return new Map(Object.entries(obj))
  }

  // The response is wrapped in ```json`` markdown because the endpoint is intended for chat clients
  private removeMarkdown(content: string): string {
    const prefix = '```json'
    const suffix = '```'
    if (content.startsWith(prefix) && content.endsWith(suffix)) {
      return content.slice(prefix.length, -suffix.length)
    } else {
      return content
    }
  }

  private getIntegrationID() {
    return process.env.NODE_ENV === 'development' ? 'copilot-embedded-experience-dev' : 'copilot-embedded-experience'
  }
}
