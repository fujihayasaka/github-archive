import {PublisherAvatar} from '@github-ui/github-models/PublisherAvatar'
import {useModels} from '../contexts/ModelsContext'
import {findModel} from '../models'
import styles from './ModelName.module.css'

export default function ModelName({modelId}: {modelId: string | undefined}) {
  const models = useModels()
  const selectedModel = modelId && findModel(modelId, models)
  const modelDisplay = selectedModel ? selectedModel.friendly_name : 'No model selected'

  return (
    <div className={styles.publisherAndModelContainer}>
      {selectedModel && (
        <PublisherAvatar
          className={styles.publisherAvatar}
          logoUrl={selectedModel.logo_url}
          darkModeIcon={selectedModel.dark_mode_icon}
          publisher={selectedModel.publisher}
          size={18}
        />
      )}
      <div className={styles.modelName}>{modelDisplay}</div>
    </div>
  )
}
