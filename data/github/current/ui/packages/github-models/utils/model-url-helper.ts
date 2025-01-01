import type {Model} from '@github-ui/marketplace-common'

export class ModelUrlHelper {
  static playgroundSuffix = 'playground'

  static modelUrl(model: Model) {
    return `/marketplace/models/${model.registry}/${model.name}`
  }

  static playgroundUrl(model: Model) {
    return `${ModelUrlHelper.modelUrl(model)}/${ModelUrlHelper.playgroundSuffix}`
  }

  static feedbackUrl(model: Model) {
    return `${ModelUrlHelper.modelUrl(model)}/feedback`
  }
}
