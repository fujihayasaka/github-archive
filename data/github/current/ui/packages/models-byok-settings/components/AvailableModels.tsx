import {useMemo} from 'react'
import invariant from 'tiny-invariant'

import type {UpdateCustomModelPayload} from '../routes/CustomModelsIndex/use-update-custom-model'
import type {CustomKey, CustomModel} from '../types'
import {AvailableModel} from './AvailableModel'

export function AvailableModels({
  customKeys,
  customModels,
  updateModel,
}: {
  customKeys: CustomKey[]
  customModels: CustomModel[]
  updateModel: (update: UpdateCustomModelPayload) => Promise<void>
}) {
  const customKeysById = useMemo(() => new Map(customKeys.map(key => [key.id, key])), [customKeys])

  return customModels.map(model => {
    const customKey = customKeysById.get(model.customKeyId)
    invariant(customKey, `Custom key with id ${model.customKeyId} not found for model ${model.slug}`)

    return <AvailableModel key={model.id} customKey={customKey} model={model} updateModel={updateModel} />
  })
}
