import type {ChatCompletionChunk, TokenUsage, TokenUsageInfo} from '../types'

/**
 * Gets the default model token usage
 */
export const getDefaultTokenUsage = (): TokenUsage => ({
  lastMessageInputTokens: 0,
  totalInputTokens: 0,
  lastMessageOutputTokens: 0,
  totalOutputTokens: 0,
})

export function updateTokenUsage(tokenUsage: TokenUsage, tokenUsageInfo?: TokenUsageInfo): TokenUsage {
  if (!tokenUsageInfo) return tokenUsage

  return {
    ...tokenUsage,
    lastMessageInputTokens: tokenUsageInfo.inputTokens,
    totalInputTokens: tokenUsage.totalInputTokens + tokenUsageInfo.inputTokens,
    lastMessageOutputTokens: tokenUsageInfo.outputTokens,
    totalOutputTokens: tokenUsage.totalOutputTokens + tokenUsageInfo.outputTokens,
  }
}

export const tokenUsageFromChunk = (chunk: ChatCompletionChunk): TokenUsageInfo => {
  return {
    inputTokens: chunk.usage?.prompt_tokens || 0,
    outputTokens: chunk.usage?.completion_tokens || 0,
  }
}

export const tokenUsageFromResponse = ({
  prompt_tokens,
  completion_tokens,
}: {
  prompt_tokens: number
  completion_tokens: number
}): TokenUsageInfo => {
  return {
    inputTokens: prompt_tokens || 0,
    outputTokens: completion_tokens || 0,
  }
}
