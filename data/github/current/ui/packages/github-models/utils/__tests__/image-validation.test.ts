import type {PlaygroundMessage} from '../../types'
import {mockModel, mockModelInputSchema} from '../../routes/playground/__tests__/mocks'
import {
  isImageAttachmentSupported,
  reachedMaxAttachments,
  supportImageWithoutText,
  SUPPORTED_IMAGE_PUBLISHERS,
} from '../image-validation'

describe('isImageAttachmentSupported', () => {
  it('should return true if the model and publisher support image attachments', () => {
    const clonedMockModel = {...mockModel}
    clonedMockModel.supported_input_modalities = ['text', 'image']
    clonedMockModel.publisher = SUPPORTED_IMAGE_PUBLISHERS[0]!
    expect(isImageAttachmentSupported(clonedMockModel)).toEqual(true)
  })

  it('should return false if the publisher does not support image attachments', () => {
    const clonedMockModel = {...mockModel}
    clonedMockModel.publisher = 'Mistral AI'
    expect(SUPPORTED_IMAGE_PUBLISHERS).not.toContain(clonedMockModel.publisher)
    clonedMockModel.supported_input_modalities = ['text', 'image']
    expect(isImageAttachmentSupported(clonedMockModel)).toEqual(false)
  })

  it('should return false if the model does not support image attachments', () => {
    expect(isImageAttachmentSupported(mockModel)).toEqual(false)
  })
})

describe('reachedMaxAttachments', () => {
  it('should return true if the model has reached the max number of image attachments', () => {
    const clonedMockModelInputSchema = {...mockModelInputSchema}
    clonedMockModelInputSchema.capabilities = {
      chat: {
        messagesWithImages: 1,
      },
    }

    const mockMessages = [
      {
        role: 'user',
        message: [
          {
            type: 'image_url',
            image_url: {
              url: 'base64 encoded image',
            },
          },
          {
            type: 'text',
            text: 'What is this?',
          },
        ],
        timestamp: new Date('2024-01-01T00:00:00+00:00'),
      },
      {
        role: 'assistant',
        message: 'test response',
        timestamp: new Date('2024-01-01T00:00:00+00:01'),
      },
    ] as PlaygroundMessage[]
    expect(reachedMaxAttachments(mockMessages, clonedMockModelInputSchema)).toEqual(true)
  })

  it('should return false if the model has not reached the max number of image attachments', () => {
    const clonedMockModelInputSchema = {...mockModelInputSchema}
    clonedMockModelInputSchema.capabilities = {
      chat: {
        messagesWithImages: 2,
      },
    }

    const mockMessages = [
      {
        role: 'user',
        message: [
          {
            type: 'image_url',
            image_url: {
              url: 'base64 encoded image',
            },
          },
          {
            type: 'text',
            text: 'What is this?',
          },
        ],
        timestamp: new Date('2024-01-01T00:00:00+00:00'),
      },
      {
        role: 'assistant',
        message: 'test response',
        timestamp: new Date('2024-01-01T00:00:00+00:01'),
      },
    ] as PlaygroundMessage[]
    expect(reachedMaxAttachments(mockMessages, clonedMockModelInputSchema)).toEqual(false)
  })

  it('should return false if the model does not have a limit on the number of image attachments', () => {
    const clonedMockModelInputSchema = {...mockModelInputSchema}

    const mockMessages = [
      {
        role: 'user',
        message: [
          {
            type: 'image_url',
            image_url: {
              url: 'base64 encoded image',
            },
          },
          {
            type: 'text',
            text: 'What is this?',
          },
        ],
        timestamp: new Date('2024-01-01T00:00:00+00:00'),
      },
      {
        role: 'assistant',
        message: 'test response',
        timestamp: new Date('2024-01-01T00:00:00+00:01'),
      },
    ] as PlaygroundMessage[]
    expect(reachedMaxAttachments(mockMessages, clonedMockModelInputSchema)).toEqual(false)
  })
})

describe('supportImageWithoutText', () => {
  it('should return true if the model is gpt-4o-mini', () => {
    const modelName = 'gpt-4o-mini'

    expect(supportImageWithoutText(modelName)).toEqual(true)
  })

  it('should return false if the model is not gpt-4o-mini', () => {
    const modelName = 'not gpt-4o-mini'

    expect(supportImageWithoutText(modelName)).toEqual(false)
  })
})
