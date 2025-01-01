import {memo, useCallback, useMemo, useState} from 'react'
import {Diff} from '@github-ui/diff-lines'
import type {DiffEntry} from '@github-ui/diff-lines/types'
import {DiffPlaceholder} from '@github-ui/diffs/DiffParts'
import {CodeownersBadge} from './CodeownersBadge'
import {MarkAsViewedButton} from './MarkAsViewedButton'
import {CommentIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {BlobActionsMenu} from './BlobActionsMenu'
import styles from './PullRequestDiffsList.module.css'
import type {PullRequest} from '../types'
import {useCollapsedDiffStatus, useUpdateCollapsedDiffStatus} from '../page-data/payloads/collapsed-diff-status'

export interface PullRequestDiffsListProps {
  headBranchName: string
  diffs: DiffEntry[]
  pullRequest: PullRequest
}

export const PullRequestDiffsList = memo(PullRequestDiffsListUnmemoized)

function PullRequestDiffsListUnmemoized({headBranchName, diffs, pullRequest}: PullRequestDiffsListProps) {
  // eslint-disable-next-line @eslint-react/naming-convention/use-state
  const [diffManuallyExpanded, __] = useState(false)
  const commentingImplementation = undefined
  const markerNavigationImplementation = undefined
  const addInjectedContextLines = () => {}

  const defaultCollapsedMap = useMemo(() => {
    const map = new Map<string, boolean>()
    for (const diff of diffs) {
      map.set(diff.path, diff.collapsed ?? false)
    }
    return map
  }, [diffs])

  const {data: collapsedMap} = useCollapsedDiffStatus(pullRequest.pathName, defaultCollapsedMap)
  const {mutate: changeCollapsedStatusForDiff} = useUpdateCollapsedDiffStatus()

  const onOptionCollapseToggle = useCallback(
    (collapsed: boolean, path: string) => {
      changeCollapsedStatusForDiff({collapsedStatus: collapsed, path, basePath: pullRequest.pathName})
    },
    [changeCollapsedStatusForDiff, pullRequest.pathName],
  )

  // TODO: get focused search result from the file tree
  const focusedSearchResult = undefined

  // TODO: get codeowners info from the API
  const codeownersInfo = {
    codeownerPath: `repo-name/blob/master/CODEOWNERS#L1`,
    ownedByCurrentUser: true,
    ownersForFile: 'pull-requests-reviewers',
    ruleForPathLine: '',
  }
  return (
    <>
      {diffs.map(diff => {
        const diffIsCollapsed =
          collapsedMap !== undefined && collapsedMap.has(diff.path) ? collapsedMap.get(diff.path) : false
        //necessary otherwiset he value we pass in for 'collapsed' below gets overwritten by whatever the default value was on the diff
        const {collapsed, ...resOfDiff} = diff
        return (
          <div key={diff.pathDigest} className={styles.entry}>
            <Diff
              focusedSearchResult={focusedSearchResult}
              collapsed={diffIsCollapsed ?? false}
              diffManuallyExpanded={diffManuallyExpanded}
              commentingImplementation={commentingImplementation}
              markerNavigationImplementation={markerNavigationImplementation}
              rightSideContent={
                <div className="d-flex flex-items-center gap-2">
                  {/*TODO: Re-work FileConversationsButton to work with our data */}
                  <IconButton icon={CommentIcon} aria-label="Comment on this file" size="small" />
                  <MarkAsViewedButton
                    path={diff.path}
                    basePath={pullRequest.pathName}
                    setIsCollapsed={value => onOptionCollapseToggle(value, diff.path)}
                    viewed={diff.reviewed}
                  />
                  <BlobActionsMenu
                    oid={diff.status === 'REMOVED' && diff.oldCommitOid ? diff.oldCommitOid : diff.newCommitOid || ''}
                    path={diff.path}
                    repo={diff.repository}
                    isViewable={!diff.isSubmodule}
                    branchName={headBranchName}
                  />
                </div>
              }
              leftSideContent={
                codeownersInfo && (
                  <CodeownersBadge
                    /* These classes need to match the flex ordering specified in DiffFileHeader,
                  code badge currently looks strange on small screens.  */
                    className="d-flex px-1 flex-items-center flex-order-2 flex-sm-order-1"
                    {...codeownersInfo}
                  />
                )
              }
              addInjectedContextLines={addInjectedContextLines}
              onOptionCollapseToggle={value => onOptionCollapseToggle(value, diff.path)}
              {...resOfDiff}
            />
          </div>
        )
      })}
      {/* DiffPlaceholder is used for the skeleton placeholder when a diff isn't loaded, it needs to be
  somewhere on the page so that it can be drawn from within the diff lines component.  */}
      <DiffPlaceholder />
    </>
  )
}
