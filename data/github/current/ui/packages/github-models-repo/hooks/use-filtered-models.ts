import type {RepoModel} from '../types'
import {useModelsQuery} from '../routes/prompt/hooks/use-models-query'
import {userHasAccessToModel} from '../utils/model-access'

// Eventually this should move to a server-side API. For now we'll determine the available models here,
// to keep this concern out of the other components
function modelAvailable(restrictedModels: string[], model: RepoModel) {
  if (model.task !== 'chat-completion') {
    return false
  }

  if (!userHasAccessToModel(model, restrictedModels)) {
    return false
  }

  return true
}

export function useFilteredModels(owner: string, repo: string, restrictedModels: string[]) {
  // Prefetch available models. As a future optimization we might restrict this only to the models needed by the
  // reference prompts, but for now we just fetch all of them. In most cases this should be cached.
  const {data: models, isLoading: isLoadingModels} = useModelsQuery(owner, repo)
  const availableModels = models?.filter(m => modelAvailable(restrictedModels, m)) || []

  return {availableModels, isLoadingModels}
}
