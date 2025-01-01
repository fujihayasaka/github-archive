import {ModelsAvatar} from '@github-ui/github-models/ModelsAvatar'
import {useModels} from '../contexts/ModelsContext'
import {findModel} from '../models'

export default function ModelName({modelId}: {modelId: string | undefined}) {
  const models = useModels()
  const selectedModel = modelId && findModel(modelId, models)
  const modelDisplay = selectedModel ? selectedModel.friendly_name : 'No model selected'

  return (
    <div className="d-flex flex-1 flex-items-center p-2">
      {selectedModel && <ModelsAvatar className="flex-shrink-0 mr-2 d-flex" model={selectedModel} size={18} />}
      <div
        className="color-fg-muted base-text-weight-semibold overflow-hidden no-wrap"
        style={{
          textOverflow: 'ellipsis',
        }}
      >
        {modelDisplay}
      </div>
    </div>
  )
}
