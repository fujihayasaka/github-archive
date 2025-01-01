import FileResultsList from '@github-ui/code-view-shared/components/files-search/FileResultsList'
import {AllShortcutsEnabledProvider} from '@github-ui/code-view-shared/contexts/AllShortcutsEnabledContext'
import {useFileQueryContext} from '@github-ui/code-view-shared/contexts/FileQueryContext'
import {useCurrentRepository} from '@github-ui/current-repository'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {type TreePane, useFileTreeControlContext} from '@github-ui/repos-file-tree-view'
import {BookIcon, PlusIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Heading, IconButton, TreeView} from '@primer/react'
import {memo, useCallback} from 'react'
import {Link, useNavigate} from 'react-router-dom'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {fileUrl, newFileUrl, overviewUrl} from '../utilities/urls'
import {FileFilter, type WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'
import styles from './FileTreeHeader.module.css'

type FileTreeHeaderProps = {
  additionalSearchableFiles: string[]
  currentFilter: FileFilter
  onAddFileClick: () => void
  onItemSelected: (path: string) => void
  onSetCurrentFilter: (filter: FileFilter) => void
} & Pick<TreePane, 'isTreeExpanded' | 'treeToggleElement'>

export const FileTreeHeader = memo(function FileTreeHeader({
  additionalSearchableFiles,
  currentFilter,
  isTreeExpanded,
  onAddFileClick,
  onItemSelected,
  onSetCurrentFilter,
  treeToggleElement,
}: FileTreeHeaderProps) {
  const {findFileWorkerPath, showOverview, path} = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {pullRequest} = useCurrentPullRequest()
  const repo = useCurrentRepository()
  const {setExpandAllFolders, setRefreshTree, setShouldFetchFolders} = useFileTreeControlContext()
  const {setQuery} = useFileQueryContext()
  const navigate = useNavigate()

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

  return (
    <div className="d-flex flex-column width-full">
      <div className="d-flex flex-row flex-justify-between flex-items-center width-full border-bottom py-2 pl-3 pr-2">
        <Heading as="h2" className="f5">
          Files
        </Heading>
        {isTreeExpanded && treeToggleElement}
      </div>
      <TreeView className="pt-2 px-3">
        <TreeView.Item
          id="overview"
          className={styles.fileTreeOverviewItem}
          onSelect={() =>
            navigate(
              overviewUrl({
                owner: repo.ownerLogin,
                repo: repo.name,
                pullNumber: pullRequest.number,
                location,
              }),
            )
          }
          current={showOverview}
        >
          <TreeView.LeadingVisual>
            <BookIcon />
          </TreeView.LeadingVisual>
          Overview
        </TreeView.Item>
      </TreeView>
      <div className="d-flex flex-row width-full px-3 pt-2 gap-2">
        <ActionMenu>
          <ActionMenu.Button className={styles.fileTreeModeButton}>{currentFilter}</ActionMenu.Button>
          <ActionMenu.Overlay width="small">
            <ActionList selectionVariant="single">
              <ActionList.Item
                onSelect={() => {
                  onSetCurrentFilter(FileFilter.PR)
                  setRefreshTree?.(true)
                  setShouldFetchFolders?.(false)
                  setExpandAllFolders?.(true)
                }}
                selected={currentFilter === FileFilter.PR}
              >
                {FileFilter.PR}
              </ActionList.Item>
              <ActionList.Item
                onSelect={() => {
                  onSetCurrentFilter(FileFilter.All)
                  setRefreshTree?.(true)
                  setShouldFetchFolders?.(true)
                  setExpandAllFolders?.(false)
                }}
                selected={currentFilter === FileFilter.All}
              >
                {FileFilter.All}
              </ActionList.Item>
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
        <IconButton
          as={Link}
          aria-label="Add a new file"
          className="ml-auto flex-shrink-0"
          icon={PlusIcon}
          to={newFileUrl({owner: repo.ownerLogin, repo: repo.name, pullNumber: pullRequest.number, location, path})}
          onClick={onAddFileClick}
        />
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
