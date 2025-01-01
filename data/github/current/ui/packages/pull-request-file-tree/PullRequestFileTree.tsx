import {DiffFileTree} from '@github-ui/diff-file-tree/file-tree'
import {CommitsDropdown} from './components/CommitsDropdown'
import {FileFilter} from './components/FileFilter'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {noop} from '@github-ui/noop'
import {
  pullRequestFilesChangedCommitPath,
  pullRequestFilesChangedCommitRangePath,
  pullRequestFilesChangedPath,
} from '@github-ui/paths'
import type {FileTreePayload} from './page-data/payloads/file-tree'
import {SelectedRefContextProvider} from './contexts/SelectedRefContext'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import type {FileFilterState} from './hooks/use-file-filtering'
import {clsx} from 'clsx'
import styles from './PullRequestFileTree.module.css'
import type {DiffDelta} from '@github-ui/diff-file-tree/diff-file-tree-helpers'

type PullRequestFileTreeProps = FileTreePayload & {
  onFileSelected?: () => void
  fileFilterState: FileFilterState
  setFileFilterState: (state: FileFilterState) => void
  filteredDiffs: DiffDelta[]
}

/*
 * This component is intended to be visually and functionally consistent with the
 * @github-ui/commits FileTree component. Look for opportunities to upstream duplicated
 * code into the shared @github-ui/diff-file-tree package.
 */
export function PullRequestFileTree({
  baseRefOid,
  commits,
  diffs,
  lastReviewOid,
  ownerLogin,
  pullRequestNumber,
  repositoryName,
  onFileSelected = noop,
  fileFilterState,
  setFileFilterState,
  filteredDiffs,
}: PullRequestFileTreeProps) {
  const onRangeUpdated = (args: {singleOrStartOid: string; endOid?: string} | undefined) => {
    let path: string
    if (!args) {
      path = pullRequestFilesChangedPath({owner: ownerLogin, repo: repositoryName, number: pullRequestNumber})
    } else if (args.endOid) {
      path = pullRequestFilesChangedCommitRangePath({
        owner: ownerLogin,
        repo: repositoryName,
        number: pullRequestNumber,
        base: args.singleOrStartOid,
        head: args.endOid,
      })
    } else {
      path = pullRequestFilesChangedCommitPath({
        owner: ownerLogin,
        repo: repositoryName,
        number: pullRequestNumber,
        commit: args.singleOrStartOid,
      })
    }

    window.location.href = path
  }
  return (
    <ErrorBoundary fallback={<span>File tree failed to load.</span>}>
      <div className={clsx('d-flex flex-column gap-2', styles['react-pr-files-file-tree'])} id="pr-file-tree">
        <SelectedRefContextProvider baseRefOid={baseRefOid} path={ssrSafeWindow?.location?.pathname ?? ''}>
          <CommitsDropdown
            baseRefOid={baseRefOid}
            commits={commits}
            lastReviewOid={lastReviewOid}
            onRangeUpdated={onRangeUpdated}
          />
        </SelectedRefContextProvider>
        <FileFilter diffs={diffs} fileFilterState={fileFilterState} setFileFilterState={setFileFilterState} />
        <h2 className="sr-only">File tree</h2>
        <DiffFileTree diffs={filteredDiffs} renderPattern="traditional" onSelect={onFileSelected} />
      </div>
    </ErrorBoundary>
  )
}
