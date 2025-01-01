import {GitHubAvatar} from '@github-ui/github-avatar'
import {PublisherAvatar} from '@github-ui/github-models/PublisherAvatar'
import {testIdProps} from '@github-ui/test-id-props'
import {Spinner} from '@primer/react'
import type {RepoModel} from '../../../types'
import styles from './CompletionMessageAvatar.module.css'

export interface CompletionMessageAvatarProps {
  isLoading?: boolean
  avatarUrl: string
  messageRole: string
  model: RepoModel
}

export function CompletionMessageAvatar({isLoading, messageRole, model, avatarUrl}: CompletionMessageAvatarProps) {
  const avatar =
    messageRole === 'assistant' || messageRole === 'error' ? (
      <PublisherAvatar
        square={false}
        logoUrl={model.logo_url}
        darkModeIcon={model.dark_mode_icon}
        publisher={model.publisher}
        size={24}
      />
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
