import {
  messageLabel,
  extractMessagePairs,
  updateMessagePairs,
  createUserMessage,
  createSystemMessage,
  createAssistantMessage,
  createErrorMessage,
} from '../message-utils'
import type {Message} from '../../types'
import type {MessagePair} from '../../../../types'

describe('message utils', () => {
  describe('create message functions', () => {
    it('createUserMessage creates a user message with timestamp', () => {
      const message = createUserMessage('Hello world')
      expect(message.role).toBe('user')
      expect(message.message).toBe('Hello world')
      expect(message.timestamp).toBeInstanceOf(Date)
    })

    it('createAssistantMessage creates an assistant message with timestamp', () => {
      const message = createAssistantMessage('Hello back')
      expect(message.role).toBe('assistant')
      expect(message.message).toBe('Hello back')
      expect(message.timestamp).toBeInstanceOf(Date)
    })

    it('createSystemMessage creates a system message with timestamp', () => {
      const message = createSystemMessage('System prompt')
      expect(message.role).toBe('system')
      expect(message.message).toBe('System prompt')
      expect(message.timestamp).toBeInstanceOf(Date)
    })

    it('createErrorMessage creates an error message with timestamp', () => {
      const message = createErrorMessage('Error occurred')
      expect(message.role).toBe('error')
      expect(message.message).toBe('Error occurred')
      expect(message.timestamp).toBeInstanceOf(Date)
    })

    it('create functions handle empty strings', () => {
      const userMsg = createUserMessage('')
      const assistantMsg = createAssistantMessage('')
      const systemMsg = createSystemMessage('')
      const errorMsg = createErrorMessage('')

      expect(userMsg.message).toBe('')
      expect(assistantMsg.message).toBe('')
      expect(systemMsg.message).toBe('')
      expect(errorMsg.message).toBe('')
    })
  })

  describe('messageLabel', () => {
    it('returns a label for a user prompt', () => {
      expect(messageLabel('user')).toBe('User prompt')
    })

    it('returns a label for a system prompt', () => {
      expect(messageLabel('system')).toBe('System prompt')
    })

    it('returns a label for other roles', () => {
      expect(messageLabel('assistant')).toBe('Assistant prompt')
      expect(messageLabel('developer')).toBe('Developer prompt')
      expect(messageLabel('tool')).toBe('Tool prompt')
      expect(messageLabel('error')).toBe('Error prompt')
    })
  })

  describe('extractMessagePairs', () => {
    it('returns empty array for empty messages', () => {
      expect(extractMessagePairs([])).toEqual([])
    })

    it('returns empty array when no pairs exist', () => {
      const messages: Message[] = [createSystemMessage('System message'), createUserMessage('User message')]
      expect(extractMessagePairs(messages)).toEqual([])
    })

    it('skips the first user message (main prompt)', () => {
      const messages: Message[] = [
        createSystemMessage('System message'),
        createUserMessage('Main prompt'),
        createAssistantMessage('Response'),
        createUserMessage('Follow-up'),
      ]
      const result = extractMessagePairs(messages)
      expect(result).toEqual([
        {
          assistant: 'Response',
          user: 'Follow-up',
        },
      ])
    })

    it('extracts multiple assistant-user pairs', () => {
      const messages: Message[] = [
        createSystemMessage('System message'),
        createUserMessage('Main prompt'),
        createAssistantMessage('First response'),
        createUserMessage('First follow-up'),
        createAssistantMessage('Second response'),
        createUserMessage('Second follow-up'),
      ]
      const result = extractMessagePairs(messages)
      expect(result).toEqual([
        {
          assistant: 'First response',
          user: 'First follow-up',
        },
        {
          assistant: 'Second response',
          user: 'Second follow-up',
        },
      ])
    })

    it('handles messages with empty content', () => {
      const messages: Message[] = [
        createSystemMessage(''),
        createUserMessage('Main prompt'),
        createAssistantMessage(''),
        createUserMessage(''),
      ]
      const result = extractMessagePairs(messages)
      expect(result).toEqual([
        {
          assistant: '',
          user: '',
        },
      ])
    })

    it('handles null/undefined messages gracefully', () => {
      const messages: Array<Message | null | undefined> = [
        createSystemMessage('System'),
        createUserMessage('Main'),
        null,
        createAssistantMessage('Response'),
        undefined,
        createUserMessage('Follow-up'),
      ]
      // Cast to Message[] as the function expects, but it should handle nulls gracefully
      const result = extractMessagePairs(messages as Message[])
      // Since the null/undefined breaks the consecutive pattern, no pairs should be found
      expect(result).toEqual([])
    })
  })

  describe('updateMessagePairs', () => {
    it('preserves system message and first user message with empty pairs', () => {
      const messages: Message[] = [createSystemMessage('System prompt'), createUserMessage('Main prompt')]
      const result = updateMessagePairs(messages, [])
      expect(result).toHaveLength(2)
      expect(result[0]).toEqual(expect.objectContaining({role: 'system', message: 'System prompt'}))
      expect(result[1]).toEqual(expect.objectContaining({role: 'user', message: 'Main prompt'}))
    })

    it('adds message pairs after preserving base messages', () => {
      const messages: Message[] = [createSystemMessage('System prompt'), createUserMessage('Main prompt')]
      const pairs: MessagePair[] = [
        {assistant: 'Response 1', user: 'Follow-up 1'},
        {assistant: 'Response 2', user: 'Follow-up 2'},
      ]
      const result = updateMessagePairs(messages, pairs)
      expect(result).toHaveLength(6) // 2 base + 4 from pairs
      expect(result[0]).toEqual(expect.objectContaining({role: 'system', message: 'System prompt'}))
      expect(result[1]).toEqual(expect.objectContaining({role: 'user', message: 'Main prompt'}))
      expect(result[2]).toEqual(expect.objectContaining({role: 'assistant', message: 'Response 1'}))
      expect(result[3]).toEqual(expect.objectContaining({role: 'user', message: 'Follow-up 1'}))
      expect(result[4]).toEqual(expect.objectContaining({role: 'assistant', message: 'Response 2'}))
      expect(result[5]).toEqual(expect.objectContaining({role: 'user', message: 'Follow-up 2'}))
    })

    it('replaces existing pairs with new ones', () => {
      const messages: Message[] = [
        createSystemMessage('System prompt'),
        createUserMessage('Main prompt'),
        createAssistantMessage('Old response 1'),
        createUserMessage('Old follow-up 1'),
        createAssistantMessage('Old response 2'),
        createUserMessage('Old follow-up 2'),
      ]
      const pairs: MessagePair[] = [{assistant: 'New response', user: 'New follow-up'}]
      const result = updateMessagePairs(messages, pairs)
      expect(result).toHaveLength(4) // 2 base + 2 from new pair
      expect(result[0]).toEqual(expect.objectContaining({role: 'system', message: 'System prompt'}))
      expect(result[1]).toEqual(expect.objectContaining({role: 'user', message: 'Main prompt'}))
      expect(result[2]).toEqual(expect.objectContaining({role: 'assistant', message: 'New response'}))
      expect(result[3]).toEqual(expect.objectContaining({role: 'user', message: 'New follow-up'}))
    })

    it('handles messages with only system message', () => {
      const messages: Message[] = [createSystemMessage('System only')]
      const pairs: MessagePair[] = [{assistant: 'Response', user: 'Follow-up'}]
      const result = updateMessagePairs(messages, pairs)
      expect(result).toHaveLength(3) // 1 system + 2 from pair
      expect(result[0]).toEqual(expect.objectContaining({role: 'system', message: 'System only'}))
      expect(result[1]).toEqual(expect.objectContaining({role: 'assistant', message: 'Response'}))
      expect(result[2]).toEqual(expect.objectContaining({role: 'user', message: 'Follow-up'}))
    })

    it('handles empty messages array', () => {
      const messages: Message[] = []
      const pairs: MessagePair[] = [{assistant: 'Response', user: 'Follow-up'}]
      const result = updateMessagePairs(messages, pairs)
      expect(result).toHaveLength(2) // Only the pair
      expect(result[0]).toEqual(expect.objectContaining({role: 'assistant', message: 'Response'}))
      expect(result[1]).toEqual(expect.objectContaining({role: 'user', message: 'Follow-up'}))
    })

    it('handles null/undefined messages gracefully', () => {
      const messages: Array<Message | null | undefined> = [
        createSystemMessage('System'),
        null,
        createUserMessage('Main'),
        undefined,
      ]
      const pairs: MessagePair[] = [{assistant: 'Response', user: 'Follow-up'}]
      const result = updateMessagePairs(messages as Message[], pairs)
      expect(result).toHaveLength(4)
      expect(result[0]).toEqual(expect.objectContaining({role: 'system', message: 'System'}))
      expect(result[1]).toEqual(expect.objectContaining({role: 'user', message: 'Main'}))
      expect(result[2]).toEqual(expect.objectContaining({role: 'assistant', message: 'Response'}))
      expect(result[3]).toEqual(expect.objectContaining({role: 'user', message: 'Follow-up'}))
    })

    it('creates messages with timestamps', () => {
      const messages: Message[] = [createUserMessage('Main')]
      const pairs: MessagePair[] = [{assistant: 'Response', user: 'Follow-up'}]
      const result = updateMessagePairs(messages, pairs)

      for (const message of result) {
        expect(message.timestamp).toBeInstanceOf(Date)
      }
    })

    it('handles empty pair content', () => {
      const messages: Message[] = [createUserMessage('Main')]
      const pairs: MessagePair[] = [{assistant: '', user: ''}]
      const result = updateMessagePairs(messages, pairs)
      expect(result).toHaveLength(3)
      expect(result[1]).toEqual(expect.objectContaining({role: 'assistant', message: ''}))
      expect(result[2]).toEqual(expect.objectContaining({role: 'user', message: ''}))
    })
  })
})
