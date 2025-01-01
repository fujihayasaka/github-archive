import type {ModelInputSchema, PlaygroundMessage} from '../types'
import type {Model} from '@github-ui/marketplace-common'

// There is no guarantee that new models will accept image requests in the same format, so this array includes only
// the model families that we have accounted for so far.
export const SUPPORTED_IMAGE_FAMILIES = ['Microsoft', 'OpenAI', 'Meta']

export const reachedMaxAttachments = (messages: PlaygroundMessage[], modelInputSchema: ModelInputSchema) => {
  const hasImageLimits = modelInputSchema?.capabilities?.chat?.messagesWithImages
  const imageCount = messages.filter(
    message => Array.isArray(message.message) && message.message.filter(m => m.type === 'image_url'),
  ).length
  return hasImageLimits ? imageCount >= hasImageLimits : false
}

export function isImageAttachmentSupported(model: Model) {
  return SUPPORTED_IMAGE_FAMILIES.includes(model.model_family) && model.supported_input_modalities.includes('image')
}

export const useImageAttachmentSupported = (model: Model) => isImageAttachmentSupported(model)

// Currently only GPT-4o-mini supports an image without text
export const supportImageWithoutText = (modelName: string) => modelName === 'gpt-4o-mini'
