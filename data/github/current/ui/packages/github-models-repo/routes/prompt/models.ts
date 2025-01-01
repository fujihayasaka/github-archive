import type {RepoModel} from '../../types'

function doesModelNameMatch(targetName: string, model: RepoModel): boolean {
  const normalizedTargetName = targetName.toLowerCase()
  // Try to find a model by its name or original name (name is original_name with any `.` replaced by `-`)
  return model.original_name.toLowerCase() === normalizedTargetName || model.name.toLowerCase() === normalizedTargetName
}

function doesModelPublisherMatch(targetPublisher: string, model: RepoModel): boolean {
  return model.publisherSlug === targetPublisher.toLowerCase()
}

export function findModel(modelId: string, models: RepoModel[]): RepoModel | undefined {
  // First try to find by publisher/name. Might have been given an id like
  // 'azureml://registries/azure-openai/models/gpt-4o-mini/versions/2024-07-18' or a publisher + name combo.
  if (modelId.includes('/')) {
    const parts = modelId.split('/')
    // More parts hint we got an id string, not a publisher + name combo
    if (parts.length === 2) {
      const publisher = parts[0]!
      const name = parts[1]!
      const model = models.find(x => doesModelPublisherMatch(publisher, x) && doesModelNameMatch(name, x))
      if (model) return model
    }
  }

  // Then try to find by id
  const model = models.find(x => x.id === modelId)
  if (model) return model

  // Then by its name or original name
  return models.find(x => doesModelNameMatch(modelId, x))
}

/**
 * Get an identifier for a model to be used as the 'model' field in a prompt YAML file.
 */
export function promptModelIdentifierFor(model: Pick<RepoModel, 'publisherSlug' | 'original_name'>): string {
  return `${model.publisherSlug}/${model.original_name}`
}
