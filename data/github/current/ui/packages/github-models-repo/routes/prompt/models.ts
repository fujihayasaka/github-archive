import type {Model} from '@github-ui/marketplace-common'

export function findModel(modelId: string, models: Model[]): Model | undefined {
  // First try to find by id
  let model = models.find(x => x.id === modelId)
  if (!model) {
    // If we couldn't find a model, try to pick by the original name (name is original_name with any `.` replaced by
    // `-`)
    model = models.find(x => x.original_name === modelId)
  }

  return model
}
