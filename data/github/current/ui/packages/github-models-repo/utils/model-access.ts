import type {RepoModel} from '../types'

export const userHasAccessToModel = (model: Pick<RepoModel, 'isRestricted' | 'name'>, restrictedModels: string[]) => {
  if (model.isRestricted) {
    return restrictedModels.includes(model.name)
  }
  return true
}
