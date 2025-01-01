import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {Label, RelativeTime} from '@primer/react'
import {CommentIcon, GitMergeQueueIcon, GitPullRequestIcon, GitPullRequestDraftIcon} from '@primer/octicons-react'
import {StatusChecksRollup} from './DashboardStatusChecksRollup'
import styles from '../DashboardLists.module.css'
import type {DashboardPullRequest} from '../types'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {useMemo} from 'react'

interface PullRequestListItemProps {
  pullRequest: DashboardPullRequest
  onTitleClick: () => void
}

export function PullRequestListItem({pullRequest, onTitleClick}: PullRequestListItemProps) {
  const repoNameWithOwner = `${pullRequest.repoNameWithOwner.ownerLogin}/${pullRequest.repoNameWithOwner.name}`
  const leadingVisualIconAttributes = useMemo(() => {
    if (pullRequest.inMergeQueue) {
      return {
        icon: GitMergeQueueIcon,
        color: 'attention.fg' as const,
        'data-testid': 'icon-merge-queue',
      }
    }

    if (pullRequest.isDraft) {
      return {
        icon: GitPullRequestDraftIcon,
        color: 'fg.subtle' as const,
        'data-testid': 'icon-pull-request-draft',
      }
    }

    return {
      icon: GitPullRequestIcon,
      color: 'success.fg' as const,
      'data-testid': 'icon-pull-request',
    }
  }, [pullRequest])

  return (
    <ListItem
      title={
        <ListItemTitle
          headingClassName={styles.titleOverride}
          value={pullRequest.title}
          href={pullRequest.permalink}
          onClick={onTitleClick}
        />
      }
      metadata={
        <>
          {pullRequest.suggestedAction && (
            <ListItemMetadata>
              <Label className={styles.SuggestedActionLabel} variant="secondary">
                {pullRequest.suggestedAction}
              </Label>
            </ListItemMetadata>
          )}
          <ListItemMetadata>
            <StatusChecksRollup pullRequest={pullRequest} />
          </ListItemMetadata>
          {pullRequest.commentCount > 0 && (
            <ListItemMetadata>
              <div>
                <CommentIcon size={16} /> <span>{pullRequest.commentCount}</span>
                <span className="sr-only">{pullRequest.commentCount === 1 ? ' comment' : ' comments'}</span>
              </div>
            </ListItemMetadata>
          )}
          <ListItemMetadata>
            <RelativeTime format={'micro'} datetime={pullRequest.updatedAt} />
          </ListItemMetadata>
        </>
      }
    >
      <ListItemLeadingContent>
        <ListItemLeadingVisual className={styles.leadingVisualOverride} {...leadingVisualIconAttributes} />
      </ListItemLeadingContent>
      <ListItemMainContent>
        <ListItemDescription>{`${repoNameWithOwner}#${pullRequest.number} · Opened by ${pullRequest.author}`}</ListItemDescription>
      </ListItemMainContent>
    </ListItem>
  )
}
