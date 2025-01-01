import {PublisherAvatar} from '@github-ui/github-models/PublisherAvatar'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {Label} from '@primer/react'
import {useFilteredModels} from '../hooks/use-filtered-models'
import {findModel} from '../routes/prompt/models'
import type {ModelRepoPromptsAppPayload} from '../types'

export const PromptLabel = ({modelId}: {modelId: string | undefined}) => {
  const {repository, restrictedModels} = useAppPayload<ModelRepoPromptsAppPayload>()
  const {availableModels: models} = useFilteredModels(repository.ownerLogin, repository.name, restrictedModels)
  const selectedModel = modelId && findModel(modelId, models)
  const modelDisplay = selectedModel ? selectedModel.friendly_name : modelId

  return (
    <Label variant="secondary" size="large" className="mr-1">
      {selectedModel && (
        <PublisherAvatar
          className="flex-shrink-0 mr-2 d-flex"
          logoUrl={selectedModel.logo_url}
          darkModeIcon={selectedModel.dark_mode_icon}
          publisher={selectedModel.publisher}
          size={18}
        />
      )}

      {modelDisplay}
    </Label>
  )
}
