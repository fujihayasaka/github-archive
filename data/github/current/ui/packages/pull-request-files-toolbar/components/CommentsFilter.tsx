import {FilterIcon, SearchIcon, TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, TextInput} from '@primer/react'
import {clsx} from 'clsx'

import type {ThreadPreviewsPayload} from '../page-data/payloads/thread-previews'

/**
 * Data on each thread that is used to determine if it matches the current filter
 */
type ThreadFilterData = {
  authorLogin: string
  body: string
  id: string
  isResolved: boolean
  path: string
}

/**
 * Return a set of thread ids that match the current filter state
 */
export function filterComments(threads: ThreadPreviewsPayload, filterState: CommentsFilterState): Set<string> {
  const matchingThreadIds = threads.filter(thread => {
    const firstComment = thread?.firstComment
    const threadFilterData = {
      authorLogin: firstComment?.author?.login ?? '',
      body: firstComment?.body ?? '',
      id: thread?.id ?? '',
      isResolved: thread?.isResolved ?? false,
      path: thread?.path ?? '',
    }

    return filterThread(threadFilterData, filterState)
  })

  return new Set([...matchingThreadIds.map(thread => thread.id ?? '')])
}

function filterThread(threadData: ThreadFilterData, filterState: CommentsFilterState) {
  const {filterText, showResolvedThreads} = filterState
  if (!showResolvedThreads && threadData.isResolved) {
    return false
  }

  if (filterText) {
    const filterTextLower = filterText.toLowerCase()
    if (
      !threadData.authorLogin.toLowerCase().includes(filterTextLower) &&
      !threadData.body.toLowerCase().includes(filterTextLower) &&
      !threadData.path.toLowerCase().includes(filterTextLower)
    ) {
      return false
    }
  }

  return true
}

/**
 * The state values of the comments filter
 */
export type CommentsFilterState = {
  filterText: string
  showResolvedThreads: boolean
}

const defaultFilterState: CommentsFilterState = {
  filterText: '',
  showResolvedThreads: true,
}

export function getDefaultFilterState(): CommentsFilterState {
  return {...defaultFilterState}
}

type CommentsFilterProps = {
  className?: string
  filterState: CommentsFilterState
  onFilterStateChange: (filterState: CommentsFilterState) => void
}

export function CommentsFilter({className, filterState, onFilterStateChange}: CommentsFilterProps) {
  const updateFilterText = (filterText: string) => {
    onFilterStateChange({...filterState, filterText})
  }

  const toggleResolvedFilter = () => {
    onFilterStateChange({...filterState, showResolvedThreads: !filterState.showResolvedThreads})
  }

  return (
    <div className={clsx('d-flex flex-row gap-2 flex-nowrap', className)}>
      <TextInput
        block
        aria-label="Filter comments"
        leadingVisual={SearchIcon}
        placeholder="Filter comments"
        value={filterState.filterText}
        onChange={event => updateFilterText(event.target.value)}
      />
      <ActionMenu>
        <ActionMenu.Anchor>
          <Button
            aria-label="Additional comment filters"
            className="flex-shink-0"
            leadingVisual={FilterIcon}
            trailingAction={TriangleDownIcon}
          >
            Filter
          </Button>
        </ActionMenu.Anchor>
        <ActionMenu.Overlay width="small">
          <ActionList selectionVariant="single">
            <ActionList.Item selected={filterState.showResolvedThreads} onSelect={() => toggleResolvedFilter()}>
              Show resolved comments
            </ActionList.Item>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </div>
  )
}
