import {
  pullRequestFilesChangedCommitPath,
  pullRequestFilesChangedCommitRangePath,
  pullRequestFilesChangedPath,
} from '@github-ui/paths'
import {CommitsDropdown, type CommitsDropdownProps} from './CommitsDropdown'
import type {FileTreePayload} from '../../page-data/payloads/file-tree'
import type {CommitSelection} from './CommitsSelector'

export type ChangesSelectorProps = Pick<FileTreePayload, 'ownerLogin' | 'repositoryName' | 'pullRequestNumber'> &
  Pick<CommitsDropdownProps, 'lastReviewOid' | 'commits' | 'variant'>

export function ChangesSelector({
  ownerLogin,
  repositoryName,
  pullRequestNumber,
  commits,
  lastReviewOid,
  variant,
}: ChangesSelectorProps) {
  const onRangeUpdated = (args: CommitSelection) => {
    let path: string
    if (args.type === 'unfiltered') {
      path = pullRequestFilesChangedPath({owner: ownerLogin, repo: repositoryName, number: pullRequestNumber})
    } else if (args.type === 'range') {
      // Omit the `base` from the URL when the range's base is
      // the PR's base commit
      const base = args.fromPRBase ? undefined : args.baseOid

      path = pullRequestFilesChangedCommitRangePath({
        owner: ownerLogin,
        repo: repositoryName,
        number: pullRequestNumber,
        base,
        head: args.endOid,
      })
    } else {
      // args.type === 'single'
      path = pullRequestFilesChangedCommitPath({
        owner: ownerLogin,
        repo: repositoryName,
        number: pullRequestNumber,
        commit: args.oid,
      })
    }

    window.location.href = path
  }

  return (
    <CommitsDropdown
      commits={commits}
      lastReviewOid={lastReviewOid}
      onRangeUpdated={onRangeUpdated}
      variant={variant}
    />
  )
}
