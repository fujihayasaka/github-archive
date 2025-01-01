import {useMemo, useState} from 'react'
import {DiffFileTree} from '@github-ui/diff-file-tree/file-tree'
import {getFileExtensions} from '@github-ui/diff-file-tree/diff-file-tree-helpers'
import {CommitsDropdown} from './components/CommitsDropdown'
import {FileFilter} from './components/FileFilter'
import {getMockPullRequestFileTreePageData} from './test-utils/mock-data'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'

/*
 * This component is intended to be visually and functionally consistent with the
 * @github-ui/commits FileTree component. Look for opportunities to upstream duplicated
 * code into the shared @github-ui/diff-file-tree package.
 */
export function PullRequestFileTree() {
  const {
    baseRefOid,
    commitOids,
    commits,
    diffs,
    onFileSelected,
    onFileExtensionsChange,
    onFilterTextChange,
    onRangeUpdated,
    unselectedFileExtensions,
  } = getMockPullRequestFileTreePageData()
  const [filterText, setFilterText] = useState('')
  const fileExtensions = useMemo(() => getFileExtensions(diffs), [diffs])

  const onFilterSearchChange = (newQuery: string) => {
    setFilterText(newQuery)
    onFilterTextChange(newQuery)
  }

  return (
    <ErrorBoundary fallback={<span>File tree failed to load.</span>}>
      <div className="d-flex flex-column gap-2">
        <CommitsDropdown
          baseRefOid={baseRefOid}
          commitOids={commitOids}
          commits={commits}
          onRangeUpdated={onRangeUpdated}
        />
        <FileFilter
          filterText={filterText}
          onFilterTextChange={onFilterSearchChange}
          fileExtensions={fileExtensions}
          unselectedFileExtensions={unselectedFileExtensions}
          onFileExtensionsChange={onFileExtensionsChange}
        />
        <h2 className="sr-only">File tree</h2>
        <DiffFileTree diffs={diffs} renderPattern="traditional" onSelect={onFileSelected} />
      </div>
    </ErrorBoundary>
  )
}
