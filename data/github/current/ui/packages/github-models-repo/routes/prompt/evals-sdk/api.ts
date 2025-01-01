export const MessageRoleValues = ['user', 'system', 'assistant', 'error', 'tool', 'developer'] as const
export type MessageRole = (typeof MessageRoleValues)[number]

export type Message = {
  timestamp: Date
  message: string
  role: MessageRole
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
  ) => Promise<Message[]>
}
