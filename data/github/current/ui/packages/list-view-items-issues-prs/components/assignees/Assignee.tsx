import {CopilotAvatar} from '@github-ui/copilot-avatar'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {graphql, useFragment} from 'react-relay'
import styles from './Assignees.module.css'

import type {Assignee$key} from './__generated__/Assignee.graphql'
import {Link} from '@primer/react'
import {clsx} from 'clsx'
import {hovercardAttributesForActor} from '@github-ui/hovercards'
import {isFeatureEnabled} from '@github-ui/feature-flags'

type Props = {
  assignee: Assignee$key
  className?: string
  /**
   * Href getter for the assignee link
   * @param name - name of the assignee
   * @returns URL to the assignee
   */
  getAssigneeHref: (assignee: string) => string
}

export function Assignee({assignee, getAssigneeHref, className}: Props) {
  const {login, avatarUrl, isCopilot} = useFragment(
    graphql`
      fragment Assignee on Actor {
        login
        avatarUrl(size: 64)
        ... on Bot {
          # this is needed to have Copilot to show up properly if we bulk select an issue assigned to it
          # eslint-disable-next-line relay/unused-fields
          isCopilot
        }
      }
    `,
    assignee,
  )

  const displayName = isCopilot ? 'Copilot' : login
  const hovercardAttributes = hovercardAttributesForActor(login, {isCopilot})

  return (
    <Link
      aria-label={`${displayName} is assigned`}
      href={getAssigneeHref(login)}
      {...hovercardAttributes}
      className={clsx(className, 'pc-AvatarItem', styles.assigneeIconLink)}
    >
      {isCopilot && isFeatureEnabled('use_copilot_avatar') ? (
        <CopilotAvatar key={login} size={'small'} />
      ) : (
        <GitHubAvatar key={login} alt={displayName} src={avatarUrl} sx={{cursor: 'pointer'}} />
      )}
    </Link>
  )
}
