import type {Model} from '@github-ui/marketplace-common'

export function supportsStreaming(model: Model) {
  return model.name !== 'o1-mini' && model.name !== 'o1-preview'
}
