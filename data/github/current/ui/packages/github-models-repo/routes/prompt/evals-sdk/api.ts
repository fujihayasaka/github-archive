import type {TokenUsage} from '@github-ui/github-models'
import type {Message} from '../types'

export type SendMessageResponse = {
  completions: Message[]
  tokenUsage: TokenUsage
}

export interface API {
  /**
   * Prompt the given model
   * @param modelId Model to prompt
   * @param modelParameters Optional parameters to use when querying the model
   * @param messages Messages to send
   * @param s Optional abort signal
   * @returns
   */
  sendMessages: (
    modelId: string,
    modelParameters: Record<string, unknown> | undefined,
    messages: Message[],
    s?: AbortSignal,
  ) => Promise<SendMessageResponse>
}
