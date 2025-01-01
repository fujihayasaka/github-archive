import {DiffFileTree, File, type FileProps} from '@github-ui/diff-file-tree/file-tree'

import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {noop} from '@github-ui/noop'
import {clsx} from 'clsx'

import type {PullRequestFileTreeDiff} from '../../page-data/payloads/file-tree'
import {useCommentCountFromMarkersData} from '../../page-data/loaders/use-markers-data'
import type {DiffDelta, FileNode} from '@github-ui/diff-file-tree/diff-file-tree-helpers'
import {usePageDataContext} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {memo, useCallback} from 'react'

export type PullRequestFileTreeProps = {
  className?: string
  filteredDiffs: PullRequestFileTreeDiff[] // filtered diff summaries
  onFileSelected?: () => void
  fileFilter: JSX.Element
}

export const PR_FILE_TREE_ID = 'pr-file-tree'

/*
 * This component is intended to be visually and functionally consistent with the
 * @github-ui/commits FileTree component. Look for opportunities to upstream duplicated
 * code into the shared @github-ui/diff-file-tree package.
 */
export function PullRequestFileTree({
  className,
  fileFilter,
  filteredDiffs, // filtered diff summaries
  onFileSelected = noop,
}: PullRequestFileTreeProps) {
  const renderFile = useCallback((props: FileProps) => <PullRequestFile key={props.file.filePath} {...props} />, [])

  return (
    <ErrorBoundary fallback={<span>File tree failed to load.</span>}>
      <div className={clsx('d-flex flex-column', className)} id={PR_FILE_TREE_ID}>
        <div className="pb-3 pr-3">{fileFilter}</div>

        <div style={{overflowY: 'auto'}}>
          <h2 className="sr-only">File tree</h2>
          <DiffFileTree
            diffs={filteredDiffs}
            fileNodeRenderer={renderFile}
            renderPattern="traditional"
            onSelect={onFileSelected}
            className="pr-3"
          />
        </div>
      </div>
    </ErrorBoundary>
  )
}

const PullRequestFile = memo(function PullRequestFile({file, ...props}: FileProps) {
  const {basePageDataUrl: basePath} = usePageDataContext()

  const threadIds = Object.values((file.diff as PullRequestFileTreeDiff)?.markersMap ?? {}).flatMap(marker =>
    marker.threads.map(thread => thread.id),
  )

  const {data: diffCommentCount} = useCommentCountFromMarkersData({basePath, threadIDs: threadIds})

  const fileWithComments: FileNode<DiffDelta> = {
    ...file,
    diff: {
      ...file.diff,
      totalCommentsCount: diffCommentCount,
    },
  }

  return <File file={fileWithComments} {...props} />
})
