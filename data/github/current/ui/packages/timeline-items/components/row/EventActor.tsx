import {Link} from '@primer/react'
import {graphql, useFragment} from 'react-relay'

import {LABELS} from '../../constants/labels'
import {VALUES} from '../../constants/values'
import type {EventActor$key} from './__generated__/EventActor.graphql'
import {GhostActor} from './GhostActor'
import {CopilotAvatar} from '@github-ui/copilot-avatar'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {hovercardAttributesForActor} from '@github-ui/hovercards'
import styles from './row.module.css'
import {isFeatureEnabled} from '@github-ui/feature-flags'

type EventActorProps = {
  actor: EventActor$key | null
} & SharedProps

type EventActorPropsInternal = {
  actor: EventActor$key
} & SharedProps

type SharedProps = {
  showAvatarOnly: boolean
}

type EventActorBaseProps = {
  login?: string
  avatarUrl: string
  profileResourcePath?: string
  isCopilot?: boolean
  isUser?: boolean
} & SharedProps

export function EventActor({actor, ...props}: EventActorProps): JSX.Element {
  return actor ? <EventActorInternal actor={actor} {...props} /> : <GhostActor />
}

function EventActorInternal({actor, ...props}: EventActorPropsInternal): JSX.Element {
  const {login, avatarUrl, isCopilot, profileResourcePath, __typename} = useFragment(
    graphql`
      fragment EventActor on Actor {
        avatarUrl(size: 64)
        login
        profileResourcePath
        __typename
        ... on Bot {
          isCopilot
        }
      }
    `,
    actor,
  )

  const isUser = ['User', 'Organization'].includes(__typename)

  return (
    <EventActorBase
      login={login}
      avatarUrl={avatarUrl}
      profileResourcePath={profileResourcePath ?? undefined}
      isCopilot={isCopilot}
      isUser={isUser}
      {...props}
    />
  )
}

function EventActorBase({
  login,
  avatarUrl,
  profileResourcePath,
  showAvatarOnly,
  isCopilot = false,
  isUser = true,
}: EventActorBaseProps): JSX.Element {
  if (login === VALUES.ghost.login) {
    return <span>{LABELS.repositoryOwner} </span>
  } else if (!login) {
    return <span>{VALUES.ghost.login} </span>
  }

  const useHovercard = isUser || isCopilot
  const displayName = isCopilot ? VALUES.copilot.displayName : login

  return (
    <div className={styles.eventActorContainer}>
      <Link
        data-testid="actor-link"
        role="link"
        href={profileResourcePath}
        {...(useHovercard ? hovercardAttributesForActor(login, {isCopilot}) : {})}
        className={styles.eventActorLink}
        muted
      >
        {isCopilot && isFeatureEnabled('use_copilot_avatar') ? (
          <CopilotAvatar size={'small'} className={styles.alignSelfCenter} />
        ) : (
          <GitHubAvatar src={avatarUrl} size={16} className={styles.alignSelfCenter} />
        )}
        {!showAvatarOnly && <span>{displayName}</span>}
      </Link>
    </div>
  )
}
