import {debounce} from '@github/mini-throttle'
import type {DiffDelta} from '@github-ui/diff-file-tree/diff-file-tree-helpers'
import {getFileExtension, getFileExtensions} from '@github-ui/diff-file-tree/diff-file-tree-helpers'
import {type FileFilterBaseProps, FileFilterShared} from '@github-ui/diff-file-tree/file-filter'
import {DiffFileTree} from '@github-ui/diff-file-tree/file-tree'
import {getCurrentSize, ScreenSize} from '@github-ui/screen-size'
import {GlobalCommands} from '@github-ui/ui-commands'
import {memo, type ReactNode, useMemo, useRef, useState} from 'react'

import {useInlineComments} from '../../contexts/InlineCommentsContext'
import type {CommitFile} from '../../types/commit-types'

export const DIFF_FILE_TREE_ID = 'diff_file_tree'

export type PostSelectAction = 'close_tree'

export type FileTreeProps = {
  contentId: string
  diffs: CommitFile[]
  onFileSelected: (file: DiffDelta, postSelectAction?: PostSelectAction) => void
  diffsHeader: ReactNode
} & Pick<FileFilterProps, 'onFileExtensionsChange' | 'unselectedFileExtensions' | 'onFilterTextChange'>

export const FileTree = memo(FileTreeUnmemoized)

function FileTreeUnmemoized({
  contentId,
  diffs,
  onFileSelected,
  diffsHeader,
  unselectedFileExtensions,
  onFilterTextChange,
  onFileExtensionsChange,
}: FileTreeProps) {
  const [filterText, setFilterText] = useState('')
  const {getCommentCountByPath} = useInlineComments()

  const narrowDiffHeader = useRef<HTMLDivElement>(null)
  // when we focus the content we can try to return focus to the element which previously had it
  const contentFocusTarget = useRef<HTMLElement | null>(null)
  // when we focus the tree we can try to return focus to the element which previously had it
  const treeFocusTarget = useRef<HTMLElement | null>(null)

  const fileExtensions = useMemo(() => getFileExtensions(diffs), [diffs])

  let tempDiffs = diffs
  if (unselectedFileExtensions && unselectedFileExtensions.size > 0) {
    tempDiffs = tempDiffs.filter(diffEntry => !unselectedFileExtensions.has(getFileExtension(diffEntry.path)))
  }

  const filteredDiffs = (
    filterText ? tempDiffs.filter(diff => diff.path.toLowerCase().includes(filterText.toLowerCase())) : tempDiffs
  ).map(diff => {
    const commentCount = getCommentCountByPath(diff.path)

    return {
      ...diff,
      totalCommentsCount: commentCount ?? 0,
    }
  })

  const onSelect = (file: DiffDelta) => {
    // we can do this since the onselect is on the client
    const currentSize = getCurrentSize(window.innerWidth)
    const isNarrowBreakpoint = currentSize <= ScreenSize.medium
    const postSelectAction: PostSelectAction | undefined = isNarrowBreakpoint ? 'close_tree' : undefined
    onFileSelected(file, postSelectAction)
  }

  const onFilterSearchChange = (newQuery: string) => {
    setFilterText(newQuery)
    onFilterTextChange(newQuery)
  }

  function toggleFocus() {
    const diffContentElement = document.getElementById(contentId)
    const treeContentElement = document.getElementById(DIFF_FILE_TREE_ID)
    let contentFocused = false
    // the user may have moved focus from where we last put it
    if (diffContentElement?.contains(document.activeElement)) {
      //the content is focused
      contentFocused = true
    }
    if (!contentFocused) {
      //focus the content
      const focusTarget = contentFocusTarget.current || diffContentElement
      treeFocusTarget.current = treeContentElement?.contains(document.activeElement)
        ? (document.activeElement as HTMLElement)
        : null
      focusTarget?.focus()
    } else {
      // focus the tree
      const focusTarget = treeFocusTarget.current || treeContentElement
      contentFocusTarget.current = diffContentElement?.contains(document.activeElement)
        ? (document.activeElement as HTMLElement)
        : null
      focusTarget?.focus()
    }
  }
  return (
    <div className="d-flex flex-column gap-2" id={DIFF_FILE_TREE_ID} tabIndex={-1}>
      <GlobalCommands
        commands={{
          'pull-requests-diff-file-tree:focus-file-tree': toggleFocus,
        }}
      />
      <h2 className="sr-only">File tree</h2>
      <div className="d-md-none" ref={narrowDiffHeader}>
        {diffsHeader}
      </div>
      <FileFilter
        filterText={filterText}
        onFilterTextChange={onFilterSearchChange}
        fileExtensions={fileExtensions}
        unselectedFileExtensions={unselectedFileExtensions}
        onFileExtensionsChange={onFileExtensionsChange}
      />
      <DiffFileTree diffs={filteredDiffs} renderPattern="traditional" onSelect={onSelect} />
    </div>
  )
}

type FileFilterProps = {
  onFilterTextChange(filterText: string): void
  onFileExtensionsChange(type: 'selectFileExtension' | 'unselectFileExtension', extension: string): void
} & Omit<FileFilterBaseProps, 'onFilterChange'>

function FileFilter({
  filterText,
  onFilterTextChange,
  fileExtensions,
  unselectedFileExtensions,
  onFileExtensionsChange,
}: FileFilterProps) {
  const debouncedOnSearch = useRef(debounce((newQuery: string) => onFilterTextChange(newQuery), 250))

  const onFilterChange = (
    type: 'selectFileExtension' | 'unselectFileExtension',
    payload: {
      extension: string
    },
  ) => {
    onFileExtensionsChange(type, payload.extension)
  }

  return (
    <FileFilterShared
      filterText={filterText}
      fileExtensions={fileExtensions}
      unselectedFileExtensions={unselectedFileExtensions}
      onFilterTextChange={text => debouncedOnSearch.current(text)}
      onFilterChange={onFilterChange}
    />
  )
}
