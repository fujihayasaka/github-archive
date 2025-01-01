import {FileQueryProvider} from '@github-ui/code-view-shared/contexts/FileQueryContext'
import {useCanonicalObject} from '@github-ui/code-view-shared/hooks/use-canonical-object'
import type {DirectoryItem} from '@github-ui/code-view-types'
import {useCurrentRepository} from '@github-ui/current-repository'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ReposFileTreePane, type TreePane, useFileTreeControlContext} from '@github-ui/repos-file-tree-view'
import {ScreenSize} from '@github-ui/screen-size'
import {useNavigate} from '@github-ui/use-navigate'
import type {FileStatus} from '@github-ui/web-commit-dialog'
import {FileStatusIcon} from '@github-ui/web-commit-dialog/FileStatusIcon'
import {useCallback, useEffect, useMemo, useState} from 'react'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {useFilesContext} from '../contexts/FilesContext'
import {OpenPanelProvider} from '../contexts/OpenPanelProvider'
import {useWorkspaceEditorUIState} from '../contexts/WorkspaceEditorUIContext'
import {useIsFileEditorPage} from '../hooks/path-match-hooks'
import {isDeleted} from '../utilities/file-status-helpers'
import {compareDirectoryItems} from '../utilities/tree-helpers'
import {fileUrl} from '../utilities/urls'
import {
  FileFilter,
  type TaskDirectoryItem,
  type TaskFileTreeData,
  type WorkspaceEditorRoutePayload,
} from '../utilities/workspace-editor-types'
import {FileTreeHeader} from './FileTreeHeader'

const WORKSPACE_EDITOR_CONTENT_HEIGHT_SX = {
  maxHeight: 'var(--workspace-editor-content-height)',
  height: 'var(--workspace-editor-content-height)',
}

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
      const localStatuses = getFileStatuses()
      let fileStatus: FileStatus | undefined
      const isDeletedLocally = isDeleted(localStatuses[item.path])
      const isDeletedInPR = isDeleted(fileStatuses[item.path])
      const isComparingAgainstHead = compareRef === pullRequest.headBranch
      const isFileInPR = item.path in fileStatuses
      if (isDeletedLocally || (!isDeletedInPR && (isComparingAgainstHead || !isFileInPR))) {
        // use local file status when:
        // - the file is deleted locally
        // - the file is not deleted in the PR and either:
        //   - compare is the PR head - this comparison includes local changes only
        //   - the file is not in the PR aka it's a new file
        fileStatus = localStatuses[item.path]
      } else {
        // otherwise use the file status from the PR
        // this means that a PR file with "A" status and "M" status locally will show as "A"
        fileStatus = fileStatuses[item.path]
      }

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
          headerSx={{p: 0}}
          paneContentsSx={{
            // Covers small screen sizes - 0 to 767px wide
            '@media screen and (max-width: 767px)': WORKSPACE_EDITOR_CONTENT_HEIGHT_SX,
            // Medium screen size (overlay) is covered by the tree's default layout
            // Covers large screens sizes - 1012px and bigger OR 1350px and bigger if the right panel is open
            '@media screen and (min-width: 1012px)': !rightPanelOpen ? WORKSPACE_EDITOR_CONTENT_HEIGHT_SX : undefined,
            '@media screen and (min-width: 1350px)': rightPanelOpen ? WORKSPACE_EDITOR_CONTENT_HEIGHT_SX : undefined,
          }}
          paneSx={{
            mr: '0 !important',
            borderRight: ['none', 'none', '1px solid'],
            borderColor: ['none', 'none', 'border.default'],
            // Covers small screen sizes - 0 to 767px wide
            '@media screen and (max-width: 767px)': WORKSPACE_EDITOR_CONTENT_HEIGHT_SX,
            // Covers medium screen sizes - 768px to 1012px OR 1350px wide if the right panel is open
            // This breakpoint range shows the tree as an overlay, hence why the height
            // requirements are different
            '@media screen and (min-width: 768px)': {
              maxHeight: 'unset',
              height: 'unset',
            },
            // Covers large screens sizes - 1012px and bigger OR 1350px and bigger if the right panel is open
            '@media screen and (min-width: 1012px)': !rightPanelOpen ? WORKSPACE_EDITOR_CONTENT_HEIGHT_SX : undefined,
            '@media screen and (min-width: 1350px)': rightPanelOpen ? WORKSPACE_EDITOR_CONTENT_HEIGHT_SX : undefined,
          }}
          treeContainerSx={{mt: 0, pb: 3, pr: 3}}
          getFileIcon={getFileIcon}
          sortDirectoryItems={directoryItems => directoryItems.sort((a, b) => compareDirectoryItems(a.data, b.data))}
          paneResizable={false}
        />
      </OpenPanelProvider>
    </FileQueryProvider>
  )
}
