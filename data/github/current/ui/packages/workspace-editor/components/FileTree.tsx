import {FileQueryProvider} from '@github-ui/code-view-shared/contexts/FileQueryContext'
import {useCanonicalObject} from '@github-ui/code-view-shared/hooks/use-canonical-object'
import type {DirectoryItem} from '@github-ui/code-view-types'
import {useCurrentRepository} from '@github-ui/current-repository'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ReposFileTreePane, type TreePane, useFileTreeControlContext} from '@github-ui/repos-file-tree-view'
// eslint-disable-next-line no-restricted-imports
import {ScreenSize} from '@github-ui/screen-size'
import {useNavigate} from '@github-ui/use-navigate'
import {FileStatusIcon} from '@github-ui/web-commit-dialog/FileStatusIcon'
import {clsx} from 'clsx'
import {useCallback, useEffect, useMemo, useState} from 'react'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {useFilesContext} from '../contexts/FilesContext'
import {OpenPanelProvider} from '../contexts/OpenPanelProvider'
import {useWorkspaceEditorUIState} from '../contexts/WorkspaceEditorUIContext'
import {useIsFileEditorPage} from '../hooks/path-match-hooks'
import {getFileStatus, isDeleted} from '../utilities/file-status-helpers'
import {compareDirectoryItems} from '../utilities/tree-helpers'
import {fileUrl} from '../utilities/urls'
import {
  FileFilter,
  type TaskDirectoryItem,
  type TaskFileTreeData,
  type WorkspaceEditorRoutePayload,
} from '../utilities/workspace-editor-types'
import styles from './FileTree.module.css'
import {FileTreeHeader} from './FileTreeHeader'

function getFlattenedDiffPaths(paths?: TaskFileTreeData) {
  if (!paths) return []

  const flattenedDiffPaths = Object.values(paths)
    .map(value => value.items)
    .flat()

  return flattenedDiffPaths
}

interface FileTreeProps extends TreePane {
  textAreaId: string
}

export function FileTree(props: FileTreeProps) {
  const {isTreeExpanded, treeToggleRef, treeToggleElement, searchBoxRef, expandTree, collapseTree, textAreaId} = props
  const payload = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {getFileStatuses, getFileTreeData, getNewFilePaths} = useFilesContext()
  const repo = useCurrentRepository()
  const {compareRef, fileStatuses = {}, path} = payload
  const {pullRequest} = useCurrentPullRequest()
  const refInfo = useCanonicalObject(payload.refInfo)
  const fileTreeId = 'repos-file-tree'
  const {rightPanel} = useWorkspaceEditorUIState()
  const prDiffPaths = getFlattenedDiffPaths(getFileTreeData(FileFilter.PR))
  const showPRFiles = payload.showOverview || prDiffPaths?.some((item: DirectoryItem) => item.path === path)
  const [currentFilter, setCurrentFilter] = useState<FileFilter>(showPRFiles ? FileFilter.PR : FileFilter.All)
  const showAllFiles = currentFilter === FileFilter.All
  const isFileEditor = useIsFileEditorPage()

  const {setExpandAllFolders, setShouldFetchFolders} = useFileTreeControlContext()
  setShouldFetchFolders?.(showAllFiles)
  setExpandAllFolders?.(!showAllFiles)

  const filteredFileTree = getFileTreeData(currentFilter)
  const newFilePaths = useMemo(() => getNewFilePaths(), [getNewFilePaths])
  const deletedFilePaths = useMemo(
    () => Object.keys(fileStatuses).filter(filePath => isDeleted(fileStatuses[filePath])),
    [fileStatuses],
  )
  const clientOnlyFilePaths = [...newFilePaths, ...deletedFilePaths]

  const navigate = useNavigate()

  const getFileIcon = useCallback(
    (item: TaskDirectoryItem) => {
      const fileStatus = getFileStatus({
        path: item.path,
        localFileStatuses: getFileStatuses(),
        prFileStatuses: fileStatuses,
        compareRef,
        headBranch: pullRequest.headBranch,
      })

      return <FileStatusIcon status={fileStatus} />
    },
    [compareRef, fileStatuses, getFileStatuses, pullRequest.headBranch],
  )

  // When a tree item is selected, collapse the tree if the screen is small
  const onTreeItemSelected = useCallback(() => {
    if (window.innerWidth < ScreenSize.large) {
      collapseTree({focus: null})
    }
  }, [collapseTree])

  const onFindFilesShortcut = useCallback(() => {
    if (window.innerWidth < ScreenSize.large) {
      expandTree({focus: 'search'})
    }
  }, [expandTree])

  const getItemUrl = useCallback(
    (item: {path: string}) => {
      return fileUrl({
        owner: repo.ownerLogin,
        repo: repo.name,
        path: item.path,
        pullNumber: pullRequest.number,
        location: window.location,
      })
    },
    [pullRequest.number, repo.name, repo.ownerLogin],
  )

  const tryNavigateToFirstFile = useCallback(
    (filter: FileFilter) => {
      const paths = getFileTreeData(filter)
      const flattenedDiffPaths = getFlattenedDiffPaths(paths)
      if (flattenedDiffPaths && !flattenedDiffPaths.some((item: DirectoryItem) => item.path === path)) {
        const firstPath = flattenedDiffPaths.find((item: DirectoryItem) => item.contentType === 'file')?.path
        if (firstPath) {
          const url = fileUrl({
            owner: repo.ownerLogin,
            repo: repo.name,
            pullNumber: pullRequest.number,
            path: firstPath,
            location,
          })
          navigate(url)
        }
      }
    },
    [getFileTreeData, navigate, path, pullRequest.number, repo.name, repo.ownerLogin],
  )

  const handleFileFilterItemSelected = useCallback(
    (selectedPath: string) => {
      const paths = getFileTreeData(FileFilter.PR)
      const flattenedDiffPaths = getFlattenedDiffPaths(paths)

      // the current file isn't in the PR file tree, switch the filter
      if (!flattenedDiffPaths.some((item: DirectoryItem) => item.path === selectedPath)) {
        setCurrentFilter(FileFilter.All)
      }
    },
    [getFileTreeData],
  )

  useEffect(() => {
    if (!isFileEditor) return

    // If the page loads with a path that is not in the tree, navigate to the first file in the tree.
    // This can happen if the user resets changes, switches between PR and All files, etc.
    tryNavigateToFirstFile(currentFilter)
  }, [currentFilter, tryNavigateToFirstFile, isFileEditor])

  const treeHeaderComponent = (
    <FileTreeHeader
      additionalSearchableFiles={clientOnlyFilePaths}
      currentFilter={currentFilter}
      isTreeExpanded={isTreeExpanded}
      onAddFileClick={onTreeItemSelected}
      onItemSelected={handleFileFilterItemSelected}
      onSetCurrentFilter={setCurrentFilter}
      treeToggleElement={treeToggleElement}
    />
  )

  const rightPanelOpen = !!rightPanel

  return (
    <FileQueryProvider>
      <OpenPanelProvider>
        <ReposFileTreePane
          id={fileTreeId}
          repo={repo}
          path={path}
          isFilePath
          refInfo={refInfo}
          clientOnlyFilePaths={clientOnlyFilePaths}
          collapseTree={collapseTree}
          showTree={isTreeExpanded}
          fileTree={filteredFileTree ?? {}}
          onItemSelected={onTreeItemSelected}
          processingTime={payload.fileTreeProcessingTime}
          treeToggleRef={treeToggleRef}
          searchBoxRef={searchBoxRef}
          foldersToFetch={payload.foldersToFetch}
          onFindFilesShortcut={onFindFilesShortcut}
          textAreaId={textAreaId}
          showFindFile={false}
          directoryNavigateOnClick={false}
          getItemUrlOverride={getItemUrl}
          showRefSelectorRow={false}
          headerContent={treeHeaderComponent}
          getFileIcon={getFileIcon}
          sortDirectoryItems={directoryItems => directoryItems.sort((a, b) => compareDirectoryItems(a.data, b.data))}
          paneResizable={false}
          headerClassName={styles.Header}
          paneClassName={clsx(
            styles.Pane,
            styles.Small,
            styles.Medium,
            !rightPanelOpen && styles.Large,
            rightPanelOpen && styles.ExtraLarge,
          )}
          treeContainerClassName={styles.TreeContainer}
          paneContentsClassName={clsx(
            styles.Small,
            // Medium screen size (overlay) is covered by the tree's default layout
            !rightPanelOpen && styles.Large,
            rightPanelOpen && styles.ExtraLarge,
          )}
        />
      </OpenPanelProvider>
    </FileQueryProvider>
  )
}
