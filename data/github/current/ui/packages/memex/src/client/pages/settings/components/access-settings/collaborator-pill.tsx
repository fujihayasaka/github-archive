import {GitHubAvatar} from '@github-ui/github-avatar'
import {testIdProps} from '@github-ui/test-id-props'
import {XIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'

import styles from './collaborator-pill.module.css'

type CollaboratorPillProps = {
  login: string
  avatarUrl: string
  id: string
  onRemove: () => void
}

export function CollaboratorPill({login, id, onRemove, avatarUrl}: CollaboratorPillProps) {
  return (
    <div key={id} className={styles.Box} {...testIdProps(`collaborator-pill-${login}`)}>
      <GitHubAvatar loading="lazy" alt={login} src={avatarUrl} className={styles.GitHubAvatar} />
      <span className={styles.Text}>{login}</span>
      <Button variant="invisible" onClick={onRemove} className={styles.Button}>
        <XIcon />
        <span className="sr-only">Remove collaborator {login}</span>
      </Button>
    </div>
  )
}
