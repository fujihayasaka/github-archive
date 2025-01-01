import type {RepositoryNWO} from '@github-ui/current-repository'
import {ListView} from '@github-ui/list-view'
import {useId} from 'react'

import type {Commit, ListCommitMessage} from '../../shared/types'
import {Panel} from '../Panel'
import styles from './CommitGroup.module.css'
import {CommitRow} from './CommitRow'
import {TimelineRow} from './TimelineRow'

export type CommitGroupProps = {
  repo: RepositoryNWO
  commits: Array<Commit<ListCommitMessage>>
  title: string
  shouldClipTimeline: boolean
  currentBlobPath?: string
  softNavToCommit?: boolean
}

/**
 * See ListView stories for a representation of this component.
 * ui/packages/list-view/src/stories/Commits.stories.tsx
 * https://ui.githubapp.com/storybook/?path=/story/recipes-list-view-dotcom-pages--commits
 */
export function CommitGroup({
  commits,
  title,
  shouldClipTimeline,
  repo,
  currentBlobPath = '',
  softNavToCommit,
}: CommitGroupProps) {
  const groupId = useId()

  return (
    <TimelineRow clipTimeline={shouldClipTimeline ? 'top' : 'none'}>
      <TimelineRow.Heading as="h3" id={groupId} title={`Commits on ${title}`} data-testid="commit-group-title" />
      <Panel className={styles.panel}>
        <ListView key={title} title={title} titleHeaderTag="h3" ariaLabelledBy={groupId}>
          {commits.map(commit => {
            return (
              <CommitRow
                key={commit.oid}
                commit={commit}
                repo={repo}
                path={currentBlobPath}
                softNavToCommit={softNavToCommit}
              />
            )
          })}
        </ListView>
      </Panel>
    </TimelineRow>
  )
}
