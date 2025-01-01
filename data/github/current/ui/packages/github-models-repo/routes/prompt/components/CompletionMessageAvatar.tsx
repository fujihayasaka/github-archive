import {GitHubAvatar} from '@github-ui/github-avatar'
import {ModelsAvatar} from '@github-ui/github-models/ModelsAvatar'
import type {Model} from '@github-ui/marketplace-common'
import {testIdProps} from '@github-ui/test-id-props'
import {Spinner} from '@primer/react'
import styles from './CompletionMessageAvatar.module.css'

export interface CompletionMessageAvatarProps {
  isLoading?: boolean
  avatarUrl: string
  messageRole: string
  model: Model
}

export function CompletionMessageAvatar({isLoading, messageRole, model, avatarUrl}: CompletionMessageAvatarProps) {
  const avatar =
    messageRole === 'assistant' || messageRole === 'error' ? (
      <ModelsAvatar square={false} model={model} size={24} />
    ) : (
      <GitHubAvatar src={avatarUrl} size={24} />
    )

  return (
    <div className="d-flex flex-items-center position-relative">
      {avatar}
      {isLoading && (
        <div className={styles.spinnerContainer} {...testIdProps('completion-message-avatar-spinner')}>
          <Spinner size="medium" className="fgColor-accent" />
        </div>
      )}
    </div>
  )
}
