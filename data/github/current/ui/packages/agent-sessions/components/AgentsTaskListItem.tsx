import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {RelativeTime} from '@primer/react'
import {GitPullRequestIcon, GitPullRequestDraftIcon, CheckCircleFillIcon, GitMergeIcon} from '@primer/octicons-react'
import styles from './AgentsTaskListItem.module.css'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {useMemo} from 'react'
import type {SessionState} from '../types/session'
import type {Pull} from '../types/pull'

export interface AgentsTaskListItemProps {
  pullRequest: Pull
  state?: SessionState
  merged: boolean
  lastSessionStartDate?: string
  revisionCount: number
}

export function AgentsTaskListItem({pullRequest, state, merged, revisionCount}: AgentsTaskListItemProps) {
  const leadingVisualIconAttributes = useMemo(() => {
    // if (pullRequest.inMergeQueue) {
    //   return {
    //     icon: CheckCircleFillIcon,
    //     color: 'success.fg' as const,
    //     'data-testid': 'icon-merge-queue',
    //   }
    // }

    if (pullRequest.reviewable_state === 'draft') {
      return {
        icon: GitPullRequestDraftIcon,
        color: 'fg.subtle' as const,
        'data-testid': 'icon-pull-request-draft',
      }
    }

    if (merged) {
      return {
        icon: GitMergeIcon,
        color: 'done.fg' as const,
        'data-testid': 'icon-pull-request-draft',
      }
    }

    if (state === 'in_progress') {
      return {
        icon: () => (
          <svg fill="none" viewBox="0 0 16 16" className="anim-rotate" aria-hidden="true" role="img">
            <path opacity=".5" d="M8 15A7 7 0 108 1a7 7 0 000 14v0z" stroke="#dbab0a" strokeWidth="2" />
            <path d="M15 8a7 7 0 01-7 7" stroke="#dbab0a" strokeWidth="2" />
            <path d="M8 12a4 4 0 100-8 4 4 0 000 8z" fill="#dbab0a" />
          </svg>
        ),
        color: 'attention.fg' as const,
        'data-testid': 'icon-pull-request',
      }
    }

    if (state === 'completed') {
      return {
        icon: CheckCircleFillIcon,
        color: 'success.fg' as const,
        'data-testid': 'icon-pull-request',
      }
    }

    return {
      icon: GitPullRequestIcon,
      color: 'success.fg' as const,
      'data-testid': 'icon-pull-request',
    }
  }, [pullRequest, merged, state])

  return (
    <ListItem
      className={styles.ListItemOverride}
      title={
        <ListItemTitle
          containerClassName={`${styles.titleContainerOverride} ${styles.pullRequest}`}
          headingClassName={styles.titleOverride}
          value={pullRequest.title}
          href={pullRequest.url}
        />
      }
      metadata={
        <>
          <ListItemMetadata>
            <RelativeTime format={'micro'} datetime={pullRequest.updated_at} />
          </ListItemMetadata>
        </>
      }
    >
      <ListItemLeadingContent>
        <ListItemLeadingVisual className={styles.leadingVisualOverride} {...leadingVisualIconAttributes} />
      </ListItemLeadingContent>
      <ListItemMainContent>
        <ListItemDescription>{`${pullRequest.repository_nwo}#${pullRequest.number} · ${revisionCount} revision${
          revisionCount > 1 ? 's' : ''
        }`}</ListItemDescription>
      </ListItemMainContent>
    </ListItem>
  )
}
