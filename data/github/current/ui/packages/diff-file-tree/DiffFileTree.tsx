import {AlertIcon, CommentIcon, InfoIcon, XCircleFillIcon} from '@primer/octicons-react'
import React, {memo, useCallback, useEffect, useRef} from 'react'
import {Link, TreeView} from '@primer/react'
import {PortalTooltip} from '@github-ui/portal-tooltip/portalled'
import type {DiffDelta, DirectoryNode, FileNode} from './diff-file-tree-helpers'
import {caseFirstCompare, getFileTree} from './diff-file-tree-helpers'
import {FileStatusIcon} from './FileStatusIcon'
import {useFileTreeTooltip} from '@github-ui/use-file-tree-tooltip'
import {parseDiffHash} from '@github-ui/diff-lines/document-hash-helpers'
import {ssrSafeDocument, ssrSafeLocation, ssrSafeWindow} from '@github-ui/ssr-utils'
import styles from './DiffFileTree.module.css'

export const DIFF_FILE_TREE_ID = 'diff_file_tree'

export interface FileProps {
  file: FileNode<DiffDelta>
  depth: number
  onSelect?(file: DiffDelta): void
  hash: string
}

const FileStatusIconItem = memo(function ({changeType}: {changeType: string}) {
  return <FileStatusIcon status={changeType} />
})

FileStatusIconItem.displayName = 'FileStatusIconItem'

export const File = memo(function File({file, depth, hash, onSelect}: FileProps) {
  const rowRef = useRef<HTMLElement>(null)
  const anchorRef = useRef<HTMLAnchorElement>(null)
  const anchorHref = `#diff-${file.diff.pathDigest}`
  const showTooltip = useFileTreeTooltip({focusRowRef: rowRef, mouseRowRef: rowRef})

  const totalCommentsCount = file.diff.totalCommentsCount ?? 0
  const maxAnnotation = file.diff.highestAnnotationLevel
  let annotationElement = null
  let annotationScreenReaderElement = null
  switch (maxAnnotation) {
    case 'WARNING':
      annotationScreenReaderElement = (
        <span className="sr-only">{totalCommentsCount > 0 ? 'and ' : ''} has warning annotations</span>
      )
      annotationElement = (
        <div className="pl-1 fgColor-attention">
          <AlertIcon />
        </div>
      )
      break
    case 'NOTICE':
      annotationScreenReaderElement = (
        <span className="sr-only">{totalCommentsCount > 0 ? 'and ' : ''} has notice annotations</span>
      )
      annotationElement = (
        <div className="pl-1 fgColor-default">
          <InfoIcon />
        </div>
      )
      break
    case 'FAILURE':
      annotationScreenReaderElement = (
        <span className="sr-only">{totalCommentsCount > 0 ? 'and ' : ''} has failure annotations</span>
      )
      annotationElement = (
        <div className="pl-1 fgColor-danger">
          <XCircleFillIcon />
        </div>
      )
      break
  }

  useEffect(() => {
    if (rowRef.current && file.diff.pathDigest === hash) {
      const timeout = window.setTimeout(() => {
        //this is obviously brittle and not testable, but is the cleanest solution to avoid jumpiness
        const fileTreeParent = ssrSafeDocument?.getElementById(DIFF_FILE_TREE_ID)?.parentElement
        const rowHeight = rowRef.current!.offsetTop
        const innerWindowHeight = ssrSafeWindow?.innerHeight ?? 0
        const usableHeight = innerWindowHeight / 2
        if (fileTreeParent) fileTreeParent.scrollTop = rowHeight - usableHeight
      }, 0)

      return () => {
        window.clearTimeout(timeout)
      }
    }
  }, [file.diff.pathDigest, hash])

  const onSelectItem = useCallback(
    (e: React.MouseEvent<HTMLElement> | React.KeyboardEvent<HTMLElement>) => {
      // Keyboard events
      if (e.nativeEvent instanceof KeyboardEvent) {
        const keyboardEvent = e as React.KeyboardEvent<HTMLElement>
        // Do nothing if item isn't currently selected
        if (rowRef?.current !== document.activeElement) {
          keyboardEvent.preventDefault()
          return
        }
        // Trigger primary action when Enter or Space are pressed
        if (keyboardEvent.key === 'Enter' || keyboardEvent.key === ' ') {
          keyboardEvent.preventDefault()
          onSelect?.(file.diff)
          anchorRef?.current?.click()
          return
        }
      }
      // Mouse events
      if (e.nativeEvent instanceof MouseEvent) {
        const mouseEvent = e as React.MouseEvent<HTMLElement>
        // Open link in a new tab on click with command or control pressed or middle click
        if (mouseEvent.metaKey || mouseEvent.ctrlKey || mouseEvent.button === 1) {
          mouseEvent.preventDefault()
          window.open(anchorHref, '_blank')
          return
        }
        // Otherwise, trigger primary action
        onSelect?.(file.diff)
        anchorRef?.current?.click()
      }
    },
    [anchorHref, file.diff, onSelect],
  )

  return (
    <>
      <TreeView.Item
        defaultExpanded
        aria-level={depth}
        current={file.diff.pathDigest === hash}
        id={file.diff.path}
        key={file.diff.pathDigest}
        onSelect={onSelectItem}
        ref={rowRef}
        className={styles['file-tree-row']}
      >
        <TreeView.LeadingVisual>
          <FileStatusIconItem changeType={file.diff.changeType} />
        </TreeView.LeadingVisual>
        <Link
          href={anchorHref}
          muted
          ref={anchorRef}
          // Intentionally setting the role to presentation to prevent link from being announced by assistive tech
          role="presentation"
          className="fgColor-default"
          // Intentionally setting tabIndex to -1 to prevent link from being focusable by assistive tech
          tabIndex={-1}
        >
          {file.fileName}
        </Link>
        {showTooltip && (
          <PortalTooltip
            data-testid={`${file.fileName}-item-tooltip`}
            id={`${file.fileName}-item-tooltip`}
            contentRef={rowRef}
            aria-label={file.fileName}
            open
            direction="ne"
          />
        )}
        {!!totalCommentsCount && (
          <span className="sr-only">
            has {totalCommentsCount < 10 ? totalCommentsCount : '9+'} {totalCommentsCount > 1 ? 'comments' : 'comment'}
          </span>
        )}
        {annotationScreenReaderElement}
        {/* Don't show the unresolved comment and annotation count if it's 0 */}
        {(!!totalCommentsCount || maxAnnotation) && (
          <TreeView.TrailingVisual>
            <div className="d-flex flex-items-center flex-row">
              {!!totalCommentsCount && (
                <>
                  <CommentIcon />
                  <div className="ml-1 text-bold fgColor-default f6">
                    {totalCommentsCount < 10 ? totalCommentsCount : '9+'}
                  </div>
                </>
              )}
              {annotationElement}
            </div>
          </TreeView.TrailingVisual>
        )}
      </TreeView.Item>
    </>
  )
})

interface DirectoryProps extends Pick<FileProps, 'onSelect' | 'hash'> {
  directory: DirectoryNode<DiffDelta>
  depth?: number
  /**
   * Overrides the default render of <File> to allow for data modification or a custom element.
   * When using this, one should try to return a <File> element from this file or something analogous in DOM structure
   */
  fileNodeRenderer?: (props: FileProps) => React.ReactNode
  leadingPath?: string
  /**
   * The pattern to use when rendering a directory.
   *
   * `grouped`: a given directory will render all of its files then all of its subdirectories
   *   ex:  contributing.md
   *        root_file.tsx
   *        directory/Component.test.tsx
   *        directory/Component.tsx
   *
   * `traditional`: a given directory will render its files and subdirectories in alphabetical order by path
   *   ex:  contributing.md
   *        directory/Component.test.tsx
   *        directory/Component.tsx
   *        root_file.tsx
   */
  renderPattern: 'traditional' | 'grouped'
}

function Directory({directory, renderPattern, depth = 0, leadingPath = '', ...fileProps}: DirectoryProps): JSX.Element {
  const pathPrefix = leadingPath ? `${leadingPath}/` : ''

  const rowRef = React.useRef<HTMLElement | null>(null)

  // Using listItemRef to fix a bug where two tooltips will stay rendered at the same time
  const listItemRef = React.useRef<HTMLElement>(null)
  const showTooltip = useFileTreeTooltip({focusRowRef: listItemRef, mouseRowRef: rowRef})

  // collapse this directory if it has no files and only one child directory
  if (!directory.files.length && directory.directories.length === 1) {
    return (
      <>
        {directory.directories.map(subDirectory => (
          <Directory
            key={subDirectory.path}
            /* Set depth to one for top-level directories that are collapsed so that tree styling is applied correctly */
            depth={depth === 0 ? 1 : depth}
            directory={subDirectory}
            leadingPath={`${pathPrefix}${directory.name}`}
            renderPattern={renderPattern}
            {...fileProps}
          />
        ))}
      </>
    )
  }

  function renderDirectoryContents() {
    if (renderPattern === 'traditional') {
      return (
        <TraditionalDirectoryRendering
          directory={directory}
          depth={depth}
          renderPattern={renderPattern}
          {...fileProps}
        />
      )
    } else {
      return (
        <GroupedDirectoryRendering directory={directory} depth={depth} renderPattern={renderPattern} {...fileProps} />
      )
    }
  }

  if (depth === 0) {
    return renderDirectoryContents()
  }

  return (
    <>
      <TreeView.Item ref={listItemRef} key={directory.path} defaultExpanded id={directory.path}>
        <TreeView.LeadingVisual>
          <TreeView.DirectoryIcon />
        </TreeView.LeadingVisual>
        <span ref={rowRef}>{`${pathPrefix}${directory.name}`}</span>
        {showTooltip && (
          <PortalTooltip
            data-testid={`${directory.name}-directory-item-tooltip`}
            id={`${directory.name}-directory-item-tooltip`}
            contentRef={listItemRef}
            aria-label={`${pathPrefix}${directory.name}`}
            open
            direction="ne"
          />
        )}
        <TreeView.SubTree>{renderDirectoryContents()}</TreeView.SubTree>
      </TreeView.Item>
    </>
  )
}

type MergedEntries = {
  path: string
  pathType: string
  node: FileNode<DiffDelta> | DirectoryNode<DiffDelta>
}

const TraditionalDirectoryRendering = memo(function TraditionalDirectoryRendering({
  directory,
  fileNodeRenderer,
  renderPattern,
  depth = 0,
  ...fileProps
}: DirectoryProps) {
  // merge files and directories into a single array
  const mergedPaths: MergedEntries[] = directory.files
    .map(file => {
      return {path: file.filePath, pathType: 'file', node: file}
    })
    .concat(
      directory.directories.map(dir => {
        return {path: dir.path, pathType: 'directory', node: dir as unknown as FileNode<DiffDelta>}
      }),
    )

  // sort the merged paths by path to render them in alphabetical order
  mergedPaths.sort((a, b) => caseFirstCompare(a.path, b.path))

  return (
    <>
      {mergedPaths.map(entry => {
        if (entry.pathType === 'file') {
          if (fileNodeRenderer) {
            return fileNodeRenderer({...fileProps, file: entry.node as FileNode<DiffDelta>, depth: depth + 1})
          }
          return <File key={entry.path} depth={depth + 1} file={entry.node as FileNode<DiffDelta>} {...fileProps} />
        } else {
          return (
            <Directory
              key={entry.path}
              depth={depth + 1}
              directory={entry.node as DirectoryNode<DiffDelta>}
              fileNodeRenderer={fileNodeRenderer}
              renderPattern={renderPattern}
              {...fileProps}
            />
          )
        }
      })}
    </>
  )
})

function GroupedDirectoryRendering({directory, depth = 0, ...fileProps}: DirectoryProps) {
  return (
    <>
      {directory.files.map(file => {
        return <File key={file.filePath} depth={depth + 1} file={file} {...fileProps} />
      })}
      {directory.directories.map(dir => {
        return <Directory key={dir.path} depth={depth + 1} directory={dir} {...fileProps} />
      })}
    </>
  )
}

export interface DiffFileTreeProps
  extends Pick<FileProps, 'onSelect'>,
    Pick<DirectoryProps, 'fileNodeRenderer' | 'renderPattern'> {
  diffs: Readonly<Array<Readonly<DiffDelta>>>
  className?: string
}

export const DiffFileTree = memo(function FileTree({
  diffs,
  fileNodeRenderer,
  renderPattern,
  className,
  ...fileProps
}: DiffFileTreeProps) {
  const fileTree = getFileTree<DiffDelta>(diffs)

  const [hash, setHash] = React.useState<string>('')

  const onHashChange = useCallback(() => {
    const windowHash = parseDiffHash(ssrSafeLocation.hash ?? '') ?? ''
    const hashWithoutPrefix = windowHash.replace('diff-', '')
    setHash(hashWithoutPrefix)
  }, [setHash])

  useEffect(() => {
    window.addEventListener('hashchange', onHashChange)
    onHashChange()
    return () => {
      window.removeEventListener('hashchange', onHashChange)
    }
  }, [onHashChange])

  return (
    <TreeView aria-label="File Tree" className={className}>
      <Directory
        directory={fileTree}
        fileNodeRenderer={fileNodeRenderer}
        renderPattern={renderPattern}
        {...fileProps}
        hash={hash}
      />
    </TreeView>
  )
})
