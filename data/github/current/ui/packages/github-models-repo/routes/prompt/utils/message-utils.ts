import type {Message, MessageContent, MessageRole} from '../types'

const createMessage = (role: MessageRole, message: MessageContent): Message => ({
  timestamp: new Date(),
  role,
  message,
})

export const createUserMessage = (message: MessageContent): Message => createMessage('user', message)
export const createErrorMessage = (message: MessageContent): Message => createMessage('error', message)
export const createAssistantMessage = (message: MessageContent): Message => createMessage('assistant', message)
export const createSystemMessage = (message: MessageContent): Message => createMessage('system', message)
