import {useResponsiveValue} from '@primer/react'
import {PlaygroundCard} from '../../../components/PlaygroundCard'
import {PublisherAvatar} from '../../../components/PublisherAvatar'
import type {ModelState} from '../../../types'
import {testIdProps} from '@github-ui/test-id-props'
import {Banner} from '@primer/react/experimental'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

import styles from './PlaygroundChatEmptyState.module.css'

interface Props {
  model: ModelState
  submitMessage: (s: string) => void
}

export default function PlaygroundChatEmptyState({model, submitMessage}: Props) {
  const {catalogData, modelInputSchema} = model

  const MAX_SUGGESTIONS = 3
  const isMobile = useResponsiveValue({narrow: true}, false)
  const iconSize = {narrow: 32, regular: 40, wide: 40}

  const formattedModelName = catalogData.name.toLowerCase().replace(/[-\s]/g, '_')
  const isModelUnstable = useFeatureFlag(`github_models_${formattedModelName}_unstable`)

  return (
    <>
      {isModelUnstable && (
        <Banner
          {...testIdProps('unstable-model-warning-banner')}
          variant="warning"
          title="Unstable model"
          hideTitle
          className="position-absolute width-full"
        >
          We&apos;re aware that {catalogData.friendly_name} is experiencing degraded performance, and our team is
          actively investigating the issue. We appreciate your patience as we work toward a resolution.
        </Banner>
      )}
      <div className="d-flex height-full flex-column flex-justify-center">
        <div className="d-flex flex-row flex-justify-center pb-3">
          <PublisherAvatar
            logoUrl={catalogData.logo_url}
            darkModeIcon={catalogData.dark_mode_icon}
            publisher={catalogData.publisher}
            size={iconSize}
          />
        </div>
        <h3 className={styles.friendlyNameText}>{catalogData.friendly_name}</h3>
        <p className={styles.summaryText}>{catalogData.summary}</p>
        {modelInputSchema?.sampleInputs && modelInputSchema.sampleInputs.length > 0 ? (
          <div {...testIdProps('sample-inputs')} aria-label="Suggested prompts" className={styles.sampleInputContainer}>
            {modelInputSchema.sampleInputs.slice(0, MAX_SUGGESTIONS).map((input, index) => {
              const content =
                input.messages && input?.messages[0] && input.messages[0].content ? input.messages[0].content : null
              if (!content) {
                return null
              }
              return (
                <PlaygroundCard
                  size={isMobile ? 'small' : 'large'}
                  sample={content}
                  // eslint-disable-next-line @eslint-react/no-array-index-key
                  key={index}
                  onAction={() => submitMessage(content)}
                />
              )
            })}
          </div>
        ) : null}
      </div>
    </>
  )
}
