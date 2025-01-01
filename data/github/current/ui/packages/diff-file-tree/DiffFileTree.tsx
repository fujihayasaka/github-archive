import {CommentIcon} from '@primer/octicons-react'
import React, {memo, useCallback, useEffect} from 'react'
import {TreeView} from '@primer/react'
import {PortalTooltip} from '@github-ui/portal-tooltip/portalled'
import type {DiffDelta, DirectoryNode, FileNode} from './diff-file-tree-helpers'
import {caseFirstCompare, getFileTree} from './diff-file-tree-helpers'
import {FileStatusIcon} from './FileStatusIcon'
import {useFileTreeTooltip} from '@github-ui/use-file-tree-tooltip'
import {parseDiffHash} from '@github-ui/diff-lines/document-hash-helpers'
import {ssrSafeDocument, ssrSafeLocation, ssrSafeWindow} from '@github-ui/ssr-utils'

const DIFF_FILE_TREE_ID = 'diff_file_tree'

interface FileProps {
  file: FileNode<DiffDelta>
  depth: number
  onSelect?(file: DiffDelta): void
  hash: string
}

const File = memo(function File({file, depth, hash, onSelect}: FileProps) {
  const rowRef = React.useRef<HTMLElement>(null)
  const showTooltip = useFileTreeTooltip({focusRowRef: rowRef, mouseRowRef: rowRef})

  const totalCommentsCount = file.diff.totalCommentsCount ?? 0
  const totalAnnotationsCount = file.diff.totalAnnotationsCount ?? 0
  const totalCommentsAndAnnotationsCount = totalCommentsCount + totalAnnotationsCount

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

  return (
    <>
      <TreeView.Item
        defaultExpanded
        aria-level={depth}
        current={file.diff.pathDigest === hash}
        id={file.diff.path}
        onSelect={() => onSelect?.(file.diff)}
        ref={rowRef}
      >
        <TreeView.LeadingVisual>
          <FileStatusIcon status={file.diff.changeType} />
        </TreeView.LeadingVisual>
        {file.fileName}
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
        {!!totalCommentsAndAnnotationsCount && (
          <span className="sr-only">
            has {totalCommentsAndAnnotationsCount < 10 ? totalCommentsAndAnnotationsCount : '9+'}{' '}
            {totalCommentsAndAnnotationsCount > 1 ? 'comments' : 'comment'}
          </span>
        )}
        {/* Don't show the unresolved comment and annotation count if it's 0 */}
        {!!totalCommentsAndAnnotationsCount && (
          <TreeView.TrailingVisual>
            <div className="d-flex flex-items-center flex-row">
              <CommentIcon />
              <div className="ml-1 text-bold fgColor-default f6">
                {totalCommentsAndAnnotationsCount < 10 ? totalCommentsAndAnnotationsCount : '9+'}
              </div>
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

function TraditionalDirectoryRendering({directory, renderPattern, depth = 0, ...fileProps}: DirectoryProps) {
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
          return <File key={entry.path} depth={depth + 1} file={entry.node as FileNode<DiffDelta>} {...fileProps} />
        } else {
          return (
            <Directory
              key={entry.path}
              depth={depth + 1}
              directory={entry.node as DirectoryNode<DiffDelta>}
              renderPattern={renderPattern}
              {...fileProps}
            />
          )
        }
      })}
    </>
  )
}

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

export interface DiffFileTreeProps extends Pick<FileProps, 'onSelect'>, Pick<DirectoryProps, 'renderPattern'> {
  diffs: Readonly<Array<Readonly<DiffDelta>>>
}

export const DiffFileTree = memo(function FileTree({diffs, renderPattern, ...fileProps}: DiffFileTreeProps) {
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
    <TreeView aria-label="File Tree">
      <Directory directory={fileTree} renderPattern={renderPattern} {...fileProps} hash={hash} />
    </TreeView>
  )
})
