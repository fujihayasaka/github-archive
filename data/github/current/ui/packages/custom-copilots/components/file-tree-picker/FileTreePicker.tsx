import {useReposAnalytics} from '@github-ui/code-view-shared/hooks/use-repos-analytics'
import {useUrlCreator} from '@github-ui/code-view-shared/hooks/use-url-creator'
import type {DirectoryItem} from '@github-ui/code-view-types'
import {PortalTooltip} from '@github-ui/portal-tooltip/portalled'
import {useFileTreeTooltip} from '@github-ui/use-file-tree-tooltip'
import {useNavigate} from '@github-ui/use-navigate'
import {AlertFillIcon, FileIcon, FileSubmoduleIcon} from '@primer/octicons-react'
import {Box, Spinner, type SxProp, TreeView, Checkbox} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import React, {useCallback, useEffect, useState, useReducer} from 'react'
import type {NavigateOptions, To} from 'react-router-dom'

import type {TreeItem} from '@github-ui/repos-file-tree-view'
import {useFetchFolder} from '../../hooks/use-fetch-folder'
import styles from './FileTreePicker.module.css'

interface CommonProps {
  clientOnlyFilePaths?: string[]
  getItemUrl: (item: DirectoryItem) => string
  onItemSelected?(item: DirectoryItem, treeItem: TreeItem<DirectoryItem>): void
  onRenderRow?(): void
  selectedItemRef?: React.Ref<HTMLElement>
  getFileTrailingVisual?: (item: DirectoryItem) =>
    | {
        trailingVisual: JSX.Element
        screenReaderText?: string
      }
    | undefined
  getFileIcon?: (item: DirectoryItem) => JSX.Element | null
}

interface FileTreePickerProps extends CommonProps, SxProp {
  rootItems: Array<TreeItem<DirectoryItem>>
  setRootItems: (rootItems: Array<TreeItem<DirectoryItem>>) => void
  processingTime: number
  loading: boolean
  fetchError: boolean
  directoryNavigateOnClick: boolean
  navigateOnClick: boolean
  sortDirectoryItems?: (items: Array<TreeItem<DirectoryItem>>) => void
  selectedItems?: Set<string>
  onSelectionChange?: (items: Set<string>) => void
  expandedPath: string
}

interface FileTreeRowProps extends CommonProps {
  isActive: boolean
  file: TreeItem<DirectoryItem>
  navigate: (to: To, options?: NavigateOptions) => void
  navigateOnClick: boolean
  isSelected?: boolean
}

interface DirectoryTreeRowProps extends CommonProps {
  directory: TreeItem<DirectoryItem>
  depth?: number
  isActive: boolean
  isAncestorOfActive: boolean
  leadingPath?: string
  navigate: (to: To, options?: NavigateOptions) => void
  navigateOnClick: boolean
  getFetchUrl: (item: DirectoryItem) => string
  itemCount?: number
  isSelected?: boolean
  selectedChildren: string[] // Changed this from selectedItems to selectedChildren
  expandedPath: string
}

interface DirectoryContentsProps extends CommonProps {
  directoryItems: Array<TreeItem<DirectoryItem>>
  leadingPath?: string
  inheritsActive?: boolean
  directoryNavigateOnClick: boolean
  navigateOnClick: boolean
  selectedChildren: string[]
  expandedPath: string
}

type SelectionAction =
  | {type: 'SELECT_FILE'; path: string}
  | {type: 'DESELECT_FILE'; path: string}
  | {type: 'SELECT_DIRECTORY'; paths: string[]}
  | {type: 'DESELECT_DIRECTORY'; paths: string[]}

function selectionReducer(state: Set<string>, action: SelectionAction): Set<string> {
  const newState = new Set(state)

  switch (action.type) {
    case 'SELECT_FILE':
      newState.add(action.path)
      break
    case 'DESELECT_FILE':
      newState.delete(action.path)
      break
    case 'SELECT_DIRECTORY':
      for (const path of action.paths) {
        newState.add(path)
      }
      break
    case 'DESELECT_DIRECTORY':
      for (const path of action.paths) {
        newState.delete(path)
      }
      break
  }

  return newState
}

function WrappedFileTreeRow({
  isActive,
  file,
  onItemSelected,
  getItemUrl,
  selectedItemRef,
  navigate,
  onRenderRow,
  getFileTrailingVisual,
  getFileIcon,
  navigateOnClick,
  isSelected,
}: FileTreeRowProps & {isSelected?: boolean}) {
  const {sendRepoClickEvent} = useReposAnalytics()
  const rowRef = React.useRef<HTMLElement>(null)
  const showTooltip = useFileTreeTooltip({focusRowRef: rowRef, mouseRowRef: rowRef})
  const isSubModule = file.data.contentType === 'submodule'
  const trailingVisualData = getFileTrailingVisual?.(file.data)

  // Add useEffect for scrolling when the item becomes active
  useEffect(() => {
    if (isActive && rowRef.current) {
      // Use requestAnimationFrame to ensure the DOM has been updated
      requestAnimationFrame(() => {
        rowRef.current?.scrollIntoView({
          block: 'center',
        })
      })
    }
  }, [isActive])

  const onSelect = React.useCallback(
    (e: React.MouseEvent<HTMLElement> | React.KeyboardEvent<HTMLElement>) => {
      if (isSubModule) {
        e.preventDefault()
        if (file.data.submoduleUrl) {
          window.location.href = file.data.submoduleUrl
        }
      } else {
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        if (e.metaKey || e.ctrlKey || (e as React.MouseEvent<HTMLElement>).button === 1) {
          window.open(getItemUrl(file.data), '_blank')
          e.preventDefault()
        } else {
          onItemSelected?.(file.data, file)
          sendRepoClickEvent('FILES_TREE.ITEM', {['item_path']: file.data.path})
          if (navigateOnClick) {
            navigate(getItemUrl(file.data))
          }
          e.stopPropagation()
        }
      }
    },
    [file, getItemUrl, isSubModule, navigate, navigateOnClick, onItemSelected, sendRepoClickEvent],
  )

  onRenderRow?.()

  // TODO: ideally we would pass as={Link} to the LinkItem if Primer supported it.
  return (
    <TreeView.Item
      ref={rowRef}
      onSelect={onSelect}
      current={isActive}
      id={`${file.data.path}-item`}
      containIntrinsicSize={!isActive ? 'auto 2rem' : undefined}
    >
      <TreeView.LeadingVisual>
        {getFileIcon ? getFileIcon(file.data) : isSubModule ? <FileSubmoduleIcon /> : <FileIcon />}
      </TreeView.LeadingVisual>
      <div className={styles.itemContainer}>
        <Checkbox
          className={styles.checkbox}
          checked={isSelected || false}
          readOnly
          aria-label={`Select ${file.data.name}`}
        />
        <span
          ref={selectedItemRef}
          style={{color: isSubModule ? 'var(--fgColor-accent, var(--color-accent-fg))' : undefined}}
        >
          <span data-testid={`${file.data.path}-file-item`}>{file.data.name}</span>
        </span>
      </div>
      {showTooltip && (
        <PortalTooltip
          data-testid={`${file.data.name}-item-tooltip`}
          id={`${file.data.name}-item-tooltip`}
          contentRef={rowRef}
          aria-label={file.data.name}
          open
          direction="ne"
        />
      )}
      {!!trailingVisualData?.screenReaderText && <span className="sr-only">{trailingVisualData.screenReaderText}</span>}
      {!!trailingVisualData?.trailingVisual && (
        <TreeView.TrailingVisual>{trailingVisualData.trailingVisual}</TreeView.TrailingVisual>
      )}
    </TreeView.Item>
  )
}

export const FileTreeRow = React.memo(WrappedFileTreeRow)

// Add underscore prefix to mark as intentionally unused
function _getSelectedChildrenForPath(selectedItems: Set<string>, path: string): string[] {
  return Array.from(selectedItems).filter(item => item === path || item.startsWith(`${path}/`))
}

// Updated helper to check directory selection state based on selected children and totalCount
function getDirectorySelectionState(
  directory: TreeItem<DirectoryItem>,
  selectedChildren?: string[],
): 'none' | 'partial' | 'all' {
  if (!selectedChildren || selectedChildren.length === 0) return 'none'

  const isDirectorySelected = selectedChildren.includes(directory.data.path)
  if (isDirectorySelected) return 'all'

  // Use totalCount from the directory item for more accurate state determination
  const expectedTotalCount = directory.data.totalCount || 0
  const selectedDescendants = selectedChildren.filter(path => path.startsWith(`${directory.data.path}/`)).length

  if (selectedDescendants === 0) return 'none'
  if (selectedDescendants === expectedTotalCount) return 'all'
  return 'partial'
}

// Add underscore prefix to mark as intentionally unused
function _getAllPathsInDirectory(directory: TreeItem<DirectoryItem>): string[] {
  const paths = [directory.data.path]
  for (const item of directory.items) {
    if (item.data.contentType === 'directory') {
      paths.push(..._getAllPathsInDirectory(item))
    } else {
      paths.push(item.data.path)
    }
  }
  return paths
}

const MemoizedCheckbox = React.memo(Checkbox)

export function WrappedDirectoryTreeRow({
  clientOnlyFilePaths,
  directory,
  isActive,
  isAncestorOfActive,
  leadingPath,
  onItemSelected,
  getItemUrl,
  getFetchUrl,
  selectedItemRef,
  navigate,
  onRenderRow,
  getFileTrailingVisual,
  getFileIcon,
  navigateOnClick,
  selectedChildren,
  expandedPath,
}: DirectoryTreeRowProps): JSX.Element {
  // Move ALL hooks to the top
  const [isExpanded, setExpanded] = useState(isAncestorOfActive)
  const {sendRepoClickEvent} = useReposAnalytics()
  const rowRef = React.useRef<HTMLElement | null>(null)
  const listItemRef = React.useRef<HTMLElement>(null)
  const showTooltip = useFileTreeTooltip({focusRowRef: listItemRef, mouseRowRef: rowRef})

  const filteredChildren = React.useMemo(
    () => selectedChildren?.filter(path => path.startsWith(`${directory.data.path}/`)),
    [selectedChildren, directory.data.path],
  )

  const selectionState = React.useMemo(
    () => getDirectorySelectionState(directory, selectedChildren),
    [directory, selectedChildren],
  )

  const [fetchFolder, incrementallyShowItems, items, loading, error, clearError, _totalCount] = useFetchFolder(
    directory,
    () => {},
    getFetchUrl,
  )

  const pathPrefix = leadingPath ? `${leadingPath}/` : ''
  const truncatedRows = _totalCount - items.length

  // Add useEffect for scrolling when the item becomes active
  useEffect(() => {
    if (isActive && rowRef.current) {
      // Use requestAnimationFrame to ensure the DOM has been updated
      requestAnimationFrame(() => {
        rowRef.current?.scrollIntoView({
          block: 'center',
        })
      })
    }
  }, [isActive])

  const onToggleExpanded = React.useCallback(
    (expanded: boolean) => {
      const willExpand = expanded && !isExpanded
      if (willExpand && !loading && !error) {
        if (directory.items.length > 100) {
          incrementallyShowItems()
        }
      }
      if (expanded !== isExpanded) {
        setExpanded(expanded)
      }
    },
    [isExpanded, loading, error, directory.items.length, incrementallyShowItems],
  )

  const onClick = React.useCallback(
    (e: React.MouseEvent<HTMLElement> | React.KeyboardEvent<HTMLElement>) => {
      if (
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        e.metaKey ||
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        e.ctrlKey ||
        ((e as React.MouseEvent<HTMLElement>).button === 1 && navigateOnClick)
      ) {
        window.open(getItemUrl(directory.data), '_blank')
        e.preventDefault()
      } else {
        onItemSelected?.(directory.data, directory)
        sendRepoClickEvent('FILES_TREE.ITEM', {['item_path']: directory.data.path})
        if (navigateOnClick) {
          navigate(getItemUrl(directory.data))
        }
        e.stopPropagation()
      }
    },
    [directory, getItemUrl, navigate, navigateOnClick, onItemSelected, sendRepoClickEvent],
  )

  // Expand when becoming active, or being an ancestor of the active path
  React.useEffect(() => {
    if (isAncestorOfActive && !isExpanded) {
      onToggleExpanded?.(true)
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps -- We don't want to reevaluate when isExpanded changes
  }, [isAncestorOfActive])

  // Collapse when all items have been removed.
  React.useEffect(() => {
    if (directory.items.length === 0 && isExpanded) {
      onToggleExpanded?.(false)
    } else if (!isExpanded && directory.autoExpand) {
      onToggleExpanded?.(true)
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps -- We don't want to reevaluate when isExpanded changes
  }, [directory.items.length])

  const setRowRef = React.useCallback(
    (refElem: HTMLElement) => {
      if (selectedItemRef && isActive) {
        ;(selectedItemRef as (item: HTMLElement) => void)(refElem)
      }
      rowRef.current = refElem
    },
    [selectedItemRef, isActive],
  )

  // Early return with proper child selection state
  if (directory.items.length === 1) {
    const firstItem = directory.items[0]
    if (firstItem && firstItem.data.contentType === 'directory') {
      return (
        <DirectoryContents
          clientOnlyFilePaths={clientOnlyFilePaths}
          directoryItems={directory.items}
          leadingPath={pathPrefix + directory.data.name}
          inheritsActive={isActive}
          onItemSelected={onItemSelected}
          selectedItemRef={selectedItemRef}
          getItemUrl={getItemUrl}
          directoryNavigateOnClick={navigateOnClick}
          navigateOnClick={navigateOnClick}
          getFileTrailingVisual={getFileTrailingVisual}
          getFileIcon={getFileIcon}
          selectedChildren={filteredChildren}
          expandedPath={expandedPath}
        />
      )
    }
  }

  onRenderRow?.()

  return (
    <TreeView.Item
      ref={listItemRef}
      expanded={isExpanded}
      onExpandedChange={onToggleExpanded}
      current={isActive}
      onSelect={onClick}
      id={`${directory.data.path}-item`}
      containIntrinsicSize={!isActive ? 'auto 2rem' : undefined}
    >
      <TreeView.LeadingVisual>
        <TreeView.DirectoryIcon />
      </TreeView.LeadingVisual>
      <div className={styles.itemContainer}>
        <MemoizedCheckbox
          className={styles.checkbox}
          checked={selectionState === 'all'}
          indeterminate={selectionState === 'partial'}
          readOnly
          aria-label={`Select ${directory.data.name}`}
          data-indeterminate={selectionState === 'partial' ? 'true' : undefined}
        />
        <span ref={setRowRef}>
          {pathPrefix && <span>{pathPrefix}</span>}
          <span data-testid={`${directory.data.path}-directory-item`}>{directory.data.name}</span>
        </span>
      </div>
      {showTooltip && (
        <PortalTooltip
          data-testid={`${directory.data.name}-directory-item-tooltip`}
          id={`${directory.data.name}-directory-item-tooltip`}
          contentRef={listItemRef}
          aria-label={`${pathPrefix}${directory.data.name}`}
          open
          direction="ne"
        />
      )}

      <TreeView.SubTree state={loading ? 'loading' : error ? 'error' : 'done'}>
        {error ? (
          <TreeView.ErrorDialog onRetry={fetchFolder} onDismiss={clearError}>
            There was an error loading the folder contents.
          </TreeView.ErrorDialog>
        ) : (
          <>
            <DirectoryContents
              clientOnlyFilePaths={clientOnlyFilePaths}
              directoryItems={items}
              onItemSelected={onItemSelected}
              selectedItemRef={selectedItemRef}
              getItemUrl={getItemUrl}
              directoryNavigateOnClick={navigateOnClick}
              navigateOnClick={navigateOnClick}
              getFileTrailingVisual={getFileTrailingVisual}
              getFileIcon={getFileIcon}
              selectedChildren={filteredChildren}
              expandedPath={expandedPath}
            />
            {truncatedRows > 0 && <ErrorTreeRow message={`${truncatedRows} entries not shown`} />}
          </>
        )}
      </TreeView.SubTree>
    </TreeView.Item>
  )
}

// Make sure DirectoryTreeRow is properly memoized
const DirectoryTreeRow = React.memo(WrappedDirectoryTreeRow, (prevProps, nextProps) => {
  // Custom comparison function for more granular control over rerenders
  return (
    prevProps.isActive === nextProps.isActive &&
    prevProps.isAncestorOfActive === nextProps.isAncestorOfActive &&
    prevProps.directory === nextProps.directory &&
    (prevProps.selectedChildren === nextProps.selectedChildren ||
      (prevProps.selectedChildren.length === 0 && nextProps.selectedChildren.length === 0)) &&
    prevProps.expandedPath === nextProps.expandedPath
  )
})

function WrappedDirectoryContents({
  clientOnlyFilePaths,
  directoryItems,
  leadingPath,
  inheritsActive,
  onItemSelected,
  selectedItemRef,
  onRenderRow,
  getItemUrl,
  getFileTrailingVisual,
  getFileIcon,
  directoryNavigateOnClick,
  navigateOnClick,
  selectedChildren,
  expandedPath,
}: DirectoryContentsProps): JSX.Element {
  const urlCreator = useUrlCreator()
  const navigate = useNavigate()
  const navigateRef = React.useRef(navigate)
  const onItemSelectedRef = React.useRef(onItemSelected)

  // Update ref when deps change
  React.useEffect(() => {
    onItemSelectedRef.current = onItemSelected
    navigateRef.current = navigate
  }, [onItemSelected, navigate])

  const handleItemSelection = React.useCallback((itemData: DirectoryItem, item: TreeItem<DirectoryItem>) => {
    onItemSelectedRef.current?.(itemData, item)
  }, [])

  // Memoize the rendered items to avoid recalculating on every render
  const renderedItems = React.useMemo(
    () =>
      directoryItems.map(item => {
        const isActive = expandedPath === item.data.path
        const isSelected = selectedChildren?.includes(item.data.path)
        const isAncestorOfActive = isActive || expandedPath.startsWith(`${item.data.path}/`)

        const itemSelectedChildren = selectedChildren?.filter(
          path => path === item.data.path || path.startsWith(`${item.data.path}/`),
        )

        if (item.data.contentType === 'directory') {
          return (
            <DirectoryTreeRow
              key={item.data.name}
              clientOnlyFilePaths={clientOnlyFilePaths}
              isActive={inheritsActive || isActive}
              isAncestorOfActive={isAncestorOfActive}
              onItemSelected={handleItemSelection}
              leadingPath={leadingPath}
              directory={item}
              getItemUrl={getItemUrl}
              getFetchUrl={urlCreator.getItemUrl}
              selectedItemRef={isAncestorOfActive ? selectedItemRef : undefined}
              navigate={navigate}
              onRenderRow={onRenderRow}
              navigateOnClick={directoryNavigateOnClick}
              getFileTrailingVisual={getFileTrailingVisual}
              getFileIcon={getFileIcon}
              itemCount={item.items.length}
              isSelected={isSelected}
              selectedChildren={itemSelectedChildren}
              expandedPath={expandedPath}
            />
          )
        }

        return (
          <FileTreeRow
            key={item.data.name}
            onItemSelected={handleItemSelection}
            file={item}
            isActive={isActive}
            getItemUrl={getItemUrl}
            selectedItemRef={isActive ? selectedItemRef : undefined}
            navigate={navigate}
            navigateOnClick={navigateOnClick}
            onRenderRow={onRenderRow}
            getFileTrailingVisual={getFileTrailingVisual}
            getFileIcon={getFileIcon}
            isSelected={isSelected}
          />
        )
      }),
    [
      directoryItems,
      expandedPath,
      selectedChildren,
      clientOnlyFilePaths,
      inheritsActive,
      handleItemSelection,
      leadingPath,
      getItemUrl,
      urlCreator.getItemUrl,
      selectedItemRef,
      navigate,
      onRenderRow,
      directoryNavigateOnClick,
      getFileTrailingVisual,
      getFileIcon,
      navigateOnClick,
    ],
  )

  return <>{renderedItems}</>
}

const DirectoryContents = React.memo(WrappedDirectoryContents)

export function FileTreePicker(props: FileTreePickerProps) {
  const {
    clientOnlyFilePaths,
    rootItems,
    fetchError,
    loading,
    onRenderRow,
    getItemUrl,
    getFileTrailingVisual,
    getFileIcon,
    expandedPath,
    onSelectionChange,
  } = props

  const [internalSelectedItems, dispatch] = useReducer(selectionReducer, new Set<string>())
  const selectedItems = props.selectedItems || internalSelectedItems

  // Memoize the common getAllFilePaths function
  const getAllFilePaths = useCallback((item: TreeItem<DirectoryItem>): string[] => {
    const pathsSet = new Set<string>()
    pathsSet.add(item.data.path)

    if (item.data.contentType === 'directory') {
      for (const child of item.items) {
        const childPaths = getAllFilePaths(child)
        for (const path of childPaths) {
          pathsSet.add(path)
        }
      }
    }

    return Array.from(pathsSet)
  }, [])

  // Create stable action dispatchers
  const handleFileSelection = useCallback(
    (path: string, isSelected: boolean) => {
      const action = isSelected ? {type: 'DESELECT_FILE' as const, path} : {type: 'SELECT_FILE' as const, path}

      if (onSelectionChange) {
        const newState = selectionReducer(selectedItems, action)
        onSelectionChange(newState)
      } else {
        dispatch(action)
      }
    },
    [onSelectionChange, selectedItems],
  )

  const handleDirectorySelection = useCallback(
    (treeItem: TreeItem<DirectoryItem>, isFullySelected: boolean) => {
      const paths = getAllFilePaths(treeItem)
      const action = isFullySelected
        ? {type: 'DESELECT_DIRECTORY' as const, paths}
        : {type: 'SELECT_DIRECTORY' as const, paths}

      if (onSelectionChange) {
        const newState = selectionReducer(selectedItems, action)
        onSelectionChange(newState)
      } else {
        dispatch(action)
      }
    },
    [getAllFilePaths, onSelectionChange, selectedItems],
  )

  // Main item selection handler that delegates to appropriate selection handler
  const handleItemSelected = useCallback(
    (item: DirectoryItem, treeItem: TreeItem<DirectoryItem>) => {
      if (item.contentType === 'directory') {
        const paths = getAllFilePaths(treeItem)
        const isFullySelected = paths.every(path => selectedItems.has(path))
        handleDirectorySelection(treeItem, isFullySelected)
      } else {
        handleFileSelection(item.path, selectedItems.has(item.path))
      }
    },
    [getAllFilePaths, handleDirectorySelection, handleFileSelection, selectedItems],
  )

  const onMouseDown = useCallback((event: React.MouseEvent) => {
    if (event.button === 1) {
      event.preventDefault()
    }
  }, [])

  return (
    <Box
      onMouseDown={onMouseDown}
      sx={{
        ...props.sx,
      }}
      data-testid="repos-file-tree-container"
    >
      {loading ? (
        <Box sx={{display: 'flex', justifyContent: 'center', p: 2}}>
          <Spinner aria-label="Loading file tree" />
        </Box>
      ) : (
        <nav aria-label="File Tree Navigation">
          <TreeView aria-label="Files">
            {fetchError && <ErrorTreeRow message="Some files could not be loaded." />}
            <DirectoryContents
              clientOnlyFilePaths={clientOnlyFilePaths}
              directoryItems={rootItems}
              onItemSelected={handleItemSelected}
              // Convert selectedItems to selectedChildren for the root level
              selectedChildren={selectedItems ? Array.from(selectedItems) : []}
              selectedItemRef={props.selectedItemRef}
              onRenderRow={onRenderRow}
              directoryNavigateOnClick={props.directoryNavigateOnClick}
              navigateOnClick={props.navigateOnClick}
              getItemUrl={getItemUrl}
              getFileTrailingVisual={getFileTrailingVisual}
              getFileIcon={getFileIcon}
              expandedPath={expandedPath}
            />
          </TreeView>
        </nav>
      )}
    </Box>
  )
}

function ErrorTreeRow({message}: {message?: string}) {
  const errorMessage = message || "Couldn't load."
  return (
    <TreeView.Item id="error-tree-row">
      <TreeView.LeadingVisual>
        <Octicon icon={AlertFillIcon} sx={{color: 'attention.fg'}} />
      </TreeView.LeadingVisual>
      <Box sx={{color: 'fg.muted'}}>{errorMessage}</Box>
    </TreeView.Item>
  )
}
