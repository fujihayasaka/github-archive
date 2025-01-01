import {FilterIcon, SearchIcon, TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, TextInput} from '@primer/react'
import {clsx} from 'clsx'

import type {Author} from '@github-ui/conversations'
import {GitHubAvatar} from '@github-ui/github-avatar'
import type {ThreadPreviewsPayload} from '../../page-data/payloads/thread-previews'

/**
 * Data on each thread that is used to determine if it matches the current filter
 */
type ThreadFilterData = {
  authorLogin: string
  body: string
  id: string
  isOutdated: boolean
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
      id: thread?.threadId ?? '',
      isResolved: thread?.isResolved ?? false,
      isOutdated: thread?.isOutdated ?? false,
      path: thread?.path ?? '',
    }

    return filterThread(threadFilterData, filterState)
  })

  return new Set([...matchingThreadIds.map(thread => thread.threadId ?? '')])
}

function filterThread(threadData: ThreadFilterData, filterState: CommentsFilterState) {
  const {filterText, showResolvedThreads} = filterState
  if (!showResolvedThreads && threadData.isResolved) {
    return false
  }

  if (!filterState.showOutdatedThreads && threadData.isOutdated) {
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

  if (filterState.selectedAuthor && threadData.authorLogin !== filterState.selectedAuthor) {
    return false
  }

  return true
}

/**
 * The state values of the comments filter
 */
export type CommentsFilterState = {
  filterText: string
  showResolvedThreads: boolean
  showOutdatedThreads: boolean
  selectedAuthor?: string
}

const defaultFilterState: CommentsFilterState = {
  filterText: '',
  showResolvedThreads: true,
  showOutdatedThreads: true,
}

export function getDefaultFilterState(): CommentsFilterState {
  return {...defaultFilterState}
}

type CommentsFilterProps = {
  authorList: Author[]
  className?: string
  filterState: CommentsFilterState
  onFilterStateChange: (filterState: CommentsFilterState) => void
}

export function CommentsFilter({authorList, className, filterState, onFilterStateChange}: CommentsFilterProps) {
  const updateFilterText = (filterText: string) => {
    onFilterStateChange({...filterState, filterText})
  }

  const toggleResolvedFilter = () => {
    onFilterStateChange({...filterState, showResolvedThreads: !filterState.showResolvedThreads})
  }

  const toggleOutdatedFilter = () => {
    onFilterStateChange({...filterState, showOutdatedThreads: !filterState.showOutdatedThreads})
  }

  const onSelectAuthor = (authorLogin: string) => {
    if (filterState.selectedAuthor === authorLogin) {
      return onFilterStateChange({...filterState, selectedAuthor: undefined})
    }

    onFilterStateChange({...filterState, selectedAuthor: authorLogin})
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
            <ActionList.Item selected={filterState.showOutdatedThreads} onSelect={() => toggleOutdatedFilter()}>
              Show outdated comments
            </ActionList.Item>
            {authorList.length > 1 && (
              <>
                <ActionList.Divider />
                <ActionList.Group>
                  <ActionList.GroupHeading>Filter by</ActionList.GroupHeading>

                  {authorList.map(author => (
                    <ActionList.Item
                      key={author.login}
                      selected={filterState.selectedAuthor === author.login}
                      onSelect={() => onSelectAuthor(author.login)}
                    >
                      <ActionList.LeadingVisual>
                        <GitHubAvatar src={author.avatarUrl} />
                      </ActionList.LeadingVisual>
                      {author.login}
                    </ActionList.Item>
                  ))}
                </ActionList.Group>
              </>
            )}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </div>
  )
}
