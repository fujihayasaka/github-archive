import type {Message, MessageContent, MessageRole} from '../types'
import type {MessagePair} from '../../../types'

const createMessage = (role: MessageRole, message: MessageContent): Message => ({
  timestamp: new Date(),
  role,
  message,
})

export const createUserMessage = (message: MessageContent): Message => createMessage('user', message)
export const createErrorMessage = (message: MessageContent): Message => createMessage('error', message)
export const createAssistantMessage = (message: MessageContent): Message => createMessage('assistant', message)
export const createSystemMessage = (message: MessageContent): Message => createMessage('system', message)

export function messageLabel(role: MessageRole): string {
  const capitalizedRole = role.charAt(0).toUpperCase() + role.slice(1)
  return `${capitalizedRole} prompt`
}

/**
 * Extracts message pairs from a messages array for editing purposes.
 * Message pairs are consecutive assistant-user message sequences.
 * The first user message is considered the prompt and excluded from pairs.
 */
export function extractMessagePairs(messages: Message[]): MessagePair[] {
  const pairs: MessagePair[] = []
  let isFirstUserMessage = true

  for (let i = 0; i < messages.length - 1; i++) {
    const current = messages[i]
    const next = messages[i + 1]

    if (!current || !next) continue

    // Skip system messages
    if (current.role === 'system') continue

    // Skip the first user message (which is the main prompt)
    if (current.role === 'user' && isFirstUserMessage) {
      isFirstUserMessage = false
      continue
    }

    // Look for consecutive assistant-user pairs
    if (current.role === 'assistant' && next.role === 'user') {
      pairs.push({
        assistant: current.message || '',
        user: next.message || '',
      })
      i++ // Skip the next message since we've processed it as part of the pair
    }
  }

  return pairs
}

/**
 * Updates message pairs within a messages array.
 * Replaces existing message pairs while preserving system message and first user message.
 */
export function updateMessagePairs(messages: Message[], newPairs: MessagePair[]): Message[] {
  const result: Message[] = []
  let foundFirstUserMessage = false

  // Keep system messages and the first user message
  for (const message of messages) {
    if (!message) continue
    if (message.role === 'system') {
      result.push(message)
    } else if (message.role === 'user' && !foundFirstUserMessage) {
      result.push(message)
      foundFirstUserMessage = true
      break
    }
  }

  // Add new message pairs
  for (const pair of newPairs) {
    if ('assistant' in pair) {
      result.push(createAssistantMessage(pair.assistant))
    }
    if ('user' in pair) {
      result.push(createUserMessage(pair.user))
    }
  }

  return result
}
