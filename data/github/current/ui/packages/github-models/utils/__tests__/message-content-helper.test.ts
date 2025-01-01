import {mockModel, mockModelInputSchema} from '../../routes/playground/__tests__/mocks'
import type {MessageContent, PlaygroundMessage} from '../../types'
import {
  createAssistantMessage,
  createErrorMessage,
  createSystemMessage,
  createToolMessage,
  createUserMessage,
  getValidMessage,
  textAndAttachmentsFromMessageContent,
  textFromMessageContent,
} from '../message-content-helper'

import {isImageAttachmentSupported, reachedMaxAttachments, supportImageWithoutText} from '../image-validation'

const mockIsImageAttachmentSupported = isImageAttachmentSupported as jest.Mock
const mockReachedMaxAttachments = reachedMaxAttachments as jest.Mock
const mockSupportImageWithoutText = supportImageWithoutText as unknown as jest.Mock

const url = 'https://github.com'

jest.mock('../image-validation', () => ({
  isImageAttachmentSupported: jest.fn(),
  reachedMaxAttachments: jest.fn(),
  supportImageWithoutText: jest.fn(),
}))

describe('textFromMessageContent', () => {
  it('returns message if message is a string', () => {
    const message: MessageContent = 'test message'
    expect(textFromMessageContent(message)).toEqual(message)
  })

  it('returns text property of second element of given array', () => {
    const message: MessageContent = [
      {type: 'image_url', image_url: {url}},
      {type: 'text', text: 'test text'},
    ]
    expect(textFromMessageContent(message)).toEqual('test text')
  })
})

describe('textAndAttachmentsFromMessageContent', () => {
  it('returns message and an empty array if message is a string', () => {
    const message: MessageContent = 'test message'
    expect(textAndAttachmentsFromMessageContent(message)).toEqual({text: message, attachments: []})
  })

  it('returns text and attachements', () => {
    const message: MessageContent = [
      {type: 'image_url', image_url: {url}},
      {type: 'text', text: 'test text'},
    ]
    expect(textAndAttachmentsFromMessageContent(message)).toEqual({text: 'test text', attachments: [url]})
  })
})

describe('getValidMessage', () => {
  describe('when text is empty', () => {
    it('returns undefined if no attachments are provided', () => {
      const text = ''
      const attachments: string[] = []
      const currentMessages: PlaygroundMessage[] = []

      const message = getValidMessage(text, attachments, currentMessages, mockModelInputSchema, mockModel)

      expect(message).toBeUndefined()
    })

    it('returns undefined if attachments are not supported by the model', () => {
      const text = ''
      const attachments = [url]
      const currentMessages: PlaygroundMessage[] = []

      mockIsImageAttachmentSupported.mockReturnValue(false)
      mockReachedMaxAttachments.mockReturnValue(false)
      mockSupportImageWithoutText.mockReturnValue(true)

      const message = getValidMessage(text, attachments, currentMessages, mockModelInputSchema, mockModel)

      expect(message).toBeUndefined()
    })

    it('returns undefined if max attachments have been reached', () => {
      const text = ''
      const attachments = [url]
      const currentMessages: PlaygroundMessage[] = [{timestamp: new Date(), message: 'test', role: 'user'}]

      mockIsImageAttachmentSupported.mockReturnValue(true)
      mockReachedMaxAttachments.mockReturnValue(true)
      mockSupportImageWithoutText.mockReturnValue(true)

      const message = getValidMessage(text, attachments, currentMessages, mockModelInputSchema, mockModel)

      expect(message).toBeUndefined()
    })

    it('returns undefined if image only is not supported', () => {
      const text = ''
      const attachments = [url]
      const currentMessages: PlaygroundMessage[] = []

      mockIsImageAttachmentSupported.mockReturnValue(true)
      mockReachedMaxAttachments.mockReturnValue(false)
      mockSupportImageWithoutText.mockReturnValue(false)

      const message = getValidMessage(text, attachments, currentMessages, mockModelInputSchema, mockModel)

      expect(message).toBeUndefined()
    })

    it('returns message with image attachment if conditions are met', () => {
      const text = ''
      const attachments = [url]
      const currentMessages: PlaygroundMessage[] = []

      mockIsImageAttachmentSupported.mockReturnValue(true)
      mockReachedMaxAttachments.mockReturnValue(false)
      mockSupportImageWithoutText.mockReturnValue(true)

      const message = getValidMessage(text, attachments, currentMessages, mockModelInputSchema, mockModel)

      expect(message).toEqual({
        timestamp: expect.any(Date),
        role: 'user',
        message: [{type: 'image_url', image_url: {url}}],
      })
    })

    it('returns message with truncated image attachments if max images per turn is exceeded', () => {
      const text = ''
      const attachments = [url, url, url]
      const currentMessages: PlaygroundMessage[] = []

      const modelInputSchema = {
        capabilities: {
          chat: {
            imagesPerTurn: 2,
          },
        },
      }

      mockIsImageAttachmentSupported.mockReturnValue(true)
      mockReachedMaxAttachments.mockReturnValue(false)
      mockSupportImageWithoutText.mockReturnValue(true)

      const message = getValidMessage(text, attachments, currentMessages, modelInputSchema, mockModel)

      expect(message).toEqual({
        timestamp: expect.any(Date),
        role: 'user',
        message: [
          {type: 'image_url', image_url: {url}},
          {type: 'image_url', image_url: {url}},
        ],
      })
    })
  })

  describe('when text is not empty', () => {
    it('returns message with text if no attachments are provided', () => {
      const text = 'test message'
      const attachments: string[] = []
      const currentMessages: PlaygroundMessage[] = []

      const message = getValidMessage(text, attachments, currentMessages, mockModelInputSchema, mockModel)

      expect(message).toEqual({
        timestamp: expect.any(Date),
        role: 'user',
        message: 'test message',
      })
    })

    it('returns message with text and image attachment if conditions are met', () => {
      const text = 'test message'
      const attachments = [url]
      const currentMessages: PlaygroundMessage[] = []

      mockIsImageAttachmentSupported.mockReturnValue(true)
      mockReachedMaxAttachments.mockReturnValue(false)
      mockSupportImageWithoutText.mockReturnValue(true)

      const message = getValidMessage(text, attachments, currentMessages, mockModelInputSchema, mockModel)

      expect(message).toEqual({
        timestamp: expect.any(Date),
        role: 'user',
        message: [
          {type: 'image_url', image_url: {url}},
          {type: 'text', text: 'test message'},
        ],
      })
    })
  })
})

describe('createUserMessage', () => {
  it('returns playground message with given user message', () => {
    const message: MessageContent = [{type: 'text', text: 'test message'}]
    const expected = {timestamp: expect.any(Date), role: 'user', message}
    expect(createUserMessage(message)).toEqual(expected)
  })
})

describe('createErrorMessage', () => {
  it('returns playground message with given error message', () => {
    const message: MessageContent = 'test error message'
    const expected = {timestamp: expect.any(Date), role: 'error', message}
    expect(createErrorMessage(message)).toEqual(expected)
  })
})

describe('createAssistantMessage', () => {
  it('returns playground message with given assistant message', () => {
    const message: MessageContent = 'test assistant message'
    const expected = {timestamp: expect.any(Date), role: 'assistant', message}
    expect(createAssistantMessage(message)).toEqual(expected)
  })
})

describe('createSystemMessage', () => {
  it('returns playground message with given system message', () => {
    const message: MessageContent = 'test system message'
    const expected = {timestamp: expect.any(Date), role: 'system', message}
    expect(createSystemMessage(message)).toEqual(expected)
  })
})

describe('createToolMessage', () => {
  it('returns playground message with given tool message and tool_call_id', () => {
    const message: MessageContent = 'test tool message'
    const tool_call_id = '123'
    const expected = {
      timestamp: expect.any(Date),
      role: 'tool',
      message,
      tool_call_id,
    }
    expect(createToolMessage(message, tool_call_id)).toEqual(expected)
  })
})
