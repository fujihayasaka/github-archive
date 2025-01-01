import FileResultsList from '@github-ui/code-view-shared/components/files-search/FileResultsList'
import {AllShortcutsEnabledProvider} from '@github-ui/code-view-shared/contexts/AllShortcutsEnabledContext'
import {useFileQueryContext} from '@github-ui/code-view-shared/contexts/FileQueryContext'
import {useCurrentRepository} from '@github-ui/current-repository'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {type TreePane, useFileTreeControlContext} from '@github-ui/repos-file-tree-view'
import {Heading} from '@primer/react'
import {memo, useCallback, useEffect} from 'react'

import {useCurrentPullRequest} from '../../workspace-editor/contexts/CurrentPullRequestProvider'
import {fileUrl} from '../../workspace-editor/utilities/urls'
import {FileFilter, type WorkspaceEditorRoutePayload} from '../../workspace-editor/utilities/workspace-editor-types'

type FileTreeHeaderProps = {
  additionalSearchableFiles: string[]
  onAddFileClick: () => void
  onItemSelected: (path: string) => void
  onSetCurrentFilter: (filter: FileFilter) => void
} & Pick<TreePane, 'isTreeExpanded' | 'treeToggleElement'>

export const FileTreeHeader = memo(function FileTreeHeader({
  additionalSearchableFiles,
  isTreeExpanded,
  onItemSelected,
  onSetCurrentFilter,
  treeToggleElement,
}: FileTreeHeaderProps) {
  const {findFileWorkerPath} = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {pullRequest} = useCurrentPullRequest()
  const repo = useCurrentRepository()
  const {setExpandAllFolders, setRefreshTree, setShouldFetchFolders} = useFileTreeControlContext()
  const {setQuery} = useFileQueryContext()

  const getItemUrl = useCallback(
    (itemPath: string) => {
      return fileUrl({
        owner: repo.ownerLogin,
        repo: repo.name,
        path: itemPath,
        pullNumber: pullRequest.number,
      })
    },
    [pullRequest.number, repo.name, repo.ownerLogin],
  )

  const handleItemSelected = useCallback(
    (selectedPath?: string) => {
      if (selectedPath) onItemSelected(selectedPath)
      setQuery('')
    },
    [onItemSelected, setQuery],
  )

  useEffect(() => {
    onSetCurrentFilter(FileFilter.PR)
    setRefreshTree?.(true)
    setShouldFetchFolders?.(true)
    setExpandAllFolders?.(false)
  }, [onSetCurrentFilter, setExpandAllFolders, setRefreshTree, setShouldFetchFolders])

  return (
    <div className="d-flex flex-column width-full">
      <div className="d-flex flex-row flex-justify-between flex-items-center width-full border-bottom py-2 pl-3 pr-2">
        <Heading as="h2" className="f5">
          Files
        </Heading>
        {isTreeExpanded && treeToggleElement}
      </div>
      {/* Disable file search shortcut for the time being */}
      <AllShortcutsEnabledProvider allShortcutsEnabled={false}>
        <FileResultsList
          actionListSx={{p: 2}}
          additionalResults={additionalSearchableFiles}
          commitOid={pullRequest.headSHA}
          config={{excludeDirectories: true, excludeSeeAllResults: true, enableOverlay: true}}
          getItemUrl={getItemUrl}
          findFileWorkerPath={findFileWorkerPath}
          sx={{mt: 2, mx: 3, mb: 3}}
          onItemSelected={handleItemSelected}
        />
      </AllShortcutsEnabledProvider>
    </div>
  )
})
