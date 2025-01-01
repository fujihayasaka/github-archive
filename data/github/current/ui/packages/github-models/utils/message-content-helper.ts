import type {Model} from '@github-ui/marketplace-common'
import type {
  ImageInputs,
  MessageContent,
  ModelInputSchema,
  PlaygroundMessage,
  PlaygroundAPIMessageAuthor,
  ToolCall,
} from '../types'
import {isImageAttachmentSupported, reachedMaxAttachments, supportImageWithoutText} from './image-validation'

export const textFromMessageContent = (message: MessageContent) => {
  if (typeof message === 'string') {
    return message
  } else {
    const text = message.find(m => m.type === 'text')
    return text?.text ?? ''
  }
}

export const textAndAttachmentsFromMessageContent = (message: MessageContent) => {
  const text = textFromMessageContent(message)
  let attachments = [] as string[]
  if (typeof message === 'object') {
    attachments = message.filter(m => m.type === 'image_url').map(m => m.image_url.url)
  }
  return {text, attachments}
}

export const getValidMessage = (
  text: string,
  attachments: string[],
  currentMessages: PlaygroundMessage[],
  modelInputSchema: ModelInputSchema,
  catalogData: Model,
): PlaygroundMessage | undefined => {
  const hasMessage = text.trim().length > 0
  const hasAttachments = attachments.length > 0
  const allowAttachments =
    isImageAttachmentSupported(catalogData) && !reachedMaxAttachments(currentMessages, modelInputSchema)
  const allowImageOnly = supportImageWithoutText(catalogData.name)

  if (!hasMessage && (!hasAttachments || !allowAttachments || !allowImageOnly)) return

  if (hasAttachments && allowAttachments) {
    // Some models have a limit on the number of images that can be sent in a single message
    const {imagesPerTurn = Infinity} = modelInputSchema?.capabilities?.chat ?? {imagesPerTurn: Infinity}

    const imageInputs = attachments
      .slice(0, imagesPerTurn)
      .map(url => ({type: 'image_url', image_url: {url}}) as ImageInputs)

    if (!hasMessage) return createUserMessage(imageInputs)

    return createUserMessage([...imageInputs, {type: 'text', text}])
  }

  return createUserMessage(text)
}

const createMessage = (role: PlaygroundAPIMessageAuthor, message: MessageContent): PlaygroundMessage => ({
  timestamp: new Date(),
  role,
  message,
})

export const createUserMessage = (message: MessageContent): PlaygroundMessage => createMessage('user', message)
export const createErrorMessage = (message: MessageContent): PlaygroundMessage => createMessage('error', message)
export const createAssistantMessage = (message: MessageContent): PlaygroundMessage =>
  createMessage('assistant', message)
export const createSystemMessage = (message: MessageContent): PlaygroundMessage => createMessage('system', message)
export const createToolMessage = (message: MessageContent, tool_call_id?: string): PlaygroundMessage => ({
  ...createMessage('tool', message),
  tool_call_id,
})
export const createToolCallMessage = (message: MessageContent, tool_calls: ToolCall[]): PlaygroundMessage => ({
  ...createMessage('tool', message),
  tool_calls,
})
