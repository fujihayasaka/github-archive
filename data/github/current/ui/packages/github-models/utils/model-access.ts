import type {Model} from '@github-ui/marketplace-common'

export const userHasAccessToModel = (model: Pick<Model, 'name' | 'isRestricted'>, restrictedModels: string[]) => {
  if (model.isRestricted) {
    return restrictedModels.includes(model.name)
  }
  return true
}
