import {GitHubAvatar} from '@github-ui/github-avatar'
import type {AssigneePickerAssignee$data} from '@github-ui/item-picker/AssigneePicker.graphql'
import {userHovercardPath} from '@github-ui/paths'
import {AvatarStack, Link} from '@primer/react'
import styles from './AssigneesMetadata.module.css'

export const AssigneesMetadata = ({assignees}: {assignees: AssigneePickerAssignee$data[]}) => {
  return (
    <AvatarStack className={styles.avatarStack}>
      {assignees.map(assignee => (
        <Link
          aria-label={`${assignee.login} is assigned`}
          href={`/${assignee.login}`}
          data-hovercard-url={userHovercardPath({owner: assignee.login})}
          key={assignee.id}
        >
          <GitHubAvatar key={assignee.login} alt={assignee.login} src={assignee.avatarUrl} className={styles.avatar} />
        </Link>
      ))}
    </AvatarStack>
  )
}
