import {announce} from '@github-ui/aria-live'
import {testIdProps} from '@github-ui/test-id-props'
import {RepoIcon} from '@primer/octicons-react'
import {type BetterSystemStyleObject, Box, Checkbox, Link, Spinner, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {memo, useEffect, useRef} from 'react'

import {ItemType} from '../../api/memex-items/item-type'
import {getInitialState} from '../../helpers/initial-state'
import {Resources} from '../../strings'
import {Blankslate} from '../common/blankslate'
import {useBulkAddItems} from './bulk-add/bulk-add-items-provider'
import styles from './item-suggestions-list.module.css'
import {SuggestedItem} from './suggested-item'

const ulStyles: BetterSystemStyleObject = {
  listStyleType: 'none',
  display: 'flex',
  flexDirection: 'column',
  contentVisibility: 'auto',
}

const NoSuggestedItems = memo(function NoSuggestedItems({hasSearchInput}: {hasSearchInput: boolean}) {
  return (
    <Blankslate
      {...testIdProps('side-panel-no-suggested-items')}
      sx={{
        backgroundColor: theme => `${theme.colors.canvas.default}`,
        display: 'flex',
        flexGrow: 1,
        m: 6,
      }}
    >
      <Octicon icon={RepoIcon} size={30} sx={{color: 'fg.muted'}} />
      <h2>No items to add</h2>
      <Text as="p" sx={{color: 'fg.muted'}}>
        {hasSearchInput ? Resources.noItemsInSearchResult : Resources.repoIsEmpty}
      </Text>
    </Blankslate>
  )
})

export const NoSuggestedRepos = memo(function NoSuggestedRepos({
  isOrganization,
  owner,
}: {
  isOrganization: boolean
  owner?: string
}) {
  return (
    <Blankslate
      {...testIdProps('side-panel-no-suggested-repos')}
      sx={{
        backgroundColor: theme => `${theme.colors.canvas.default}`,
        display: 'flex',
        flexGrow: 1,
        m: 6,
      }}
    >
      <Octicon icon={RepoIcon} size={30} sx={{color: 'fg.muted'}} />
      <h2>No repositories found</h2>
      <Text as="p" sx={{color: 'fg.muted'}}>
        Create a{' '}
        <Link inline href={isOrganization ? `/orgs/${owner}/repositories` : `/${owner}?tab=repositories`}>
          repository
        </Link>{' '}
        to get started.
      </Text>
    </Blankslate>
  )
})

const Loader = memo(function Loader() {
  return (
    <Blankslate
      sx={{
        backgroundColor: theme => `${theme.colors.canvas.default}`,
        display: 'flex',
        flexGrow: 1,
        m: 6,
      }}
    >
      <Spinner />
    </Blankslate>
  )
})

export const ItemSuggestionsList = memo(function ItemSuggestionsList() {
  const {
    selectedRepo,
    items,
    loading,
    finishedFetchingRepoItems,
    selectAllItems,
    areAllItemsSelected,
    searchQuery,
    MAX_ITEM_NUM,
  } = useBulkAddItems()

  const {projectOwner, isOrganization} = getInitialState()
  const owner = projectOwner?.name?.toLowerCase()
  const searchResultsRef = useRef<HTMLDivElement>(null)
  const ariaLiveRef = useRef<HTMLDivElement>(null)
  const previousSearch = useRef<string | undefined>(searchQuery)
  const previousRepo = useRef<typeof selectedRepo>(selectedRepo)
  const searchAttemptCount = useRef<number>(0)
  const announcedAttemptCount = useRef<number>(-1)

  // Helper function to announce search results
  const announceResults = () => {
    if (searchResultsRef.current && ariaLiveRef.current) {
      announce(searchResultsRef.current.textContent || '', {element: ariaLiveRef.current})
      announcedAttemptCount.current = searchAttemptCount.current
    }
  }

  // triggered on search submit or repo change
  useEffect(() => {
    // track search query
    if (previousSearch.current !== searchQuery) {
      previousSearch.current = searchQuery
      searchAttemptCount.current += 1
    }
    // Track repository changes
    if (previousRepo.current !== selectedRepo) {
      previousRepo.current = selectedRepo
      searchAttemptCount.current += 1
    }
  }, [searchQuery, selectedRepo])

  useEffect(() => {
    // checks that search is complete and that it's a new search
    if (loading || !finishedFetchingRepoItems) return
    if (searchAttemptCount.current === announcedAttemptCount.current) return

    const timeoutId = setTimeout(() => {
      announceResults()
    }, 0)
    return () => clearTimeout(timeoutId)
  }, [loading, finishedFetchingRepoItems])

  return (
    <Box sx={ulStyles} {...testIdProps('side-panel-suggested-items')}>
      <div role="status" aria-live="polite" ref={ariaLiveRef} className="sr-only" />
      {loading ? (
        <Loader />
      ) : items?.length === 0 && finishedFetchingRepoItems && selectedRepo ? (
        <div ref={searchResultsRef}>
          <NoSuggestedItems hasSearchInput={!!searchQuery} />
        </div>
      ) : selectedRepo ? (
        <div>
          <Box
            {...testIdProps('selection-all-items')}
            sx={{
              display: 'flex',
              borderBottom: '1px solid',
              borderColor: 'border.default',
              paddingBottom: 2,
              paddingTop: 3,
              justifyContent: 'space-between',
            }}
          >
            <Box sx={{display: 'flex'}}>
              <Box as="label" sx={{pl: 1, pr: '10px'}}>
                <Checkbox
                  aria-label={areAllItemsSelected ? 'Deselect all items' : 'Select all items'}
                  checked={areAllItemsSelected}
                  onChange={selectAllItems}
                  className={styles.Checkbox}
                />
              </Box>
              <span>{areAllItemsSelected ? 'Deselect all items' : 'Select all items'}</span>
            </Box>
            {items?.length === MAX_ITEM_NUM && (
              <Text {...testIdProps('side-panel-suggested-items-recent-count')} sx={{fontSize: 0, color: 'fg.muted'}}>
                Showing {MAX_ITEM_NUM} most recent items
              </Text>
            )}
          </Box>
          <ul>
            {items?.map(suggestedItem => {
              const repoName = selectedRepo.nameWithOwner
              return (
                <SuggestedItem
                  item={suggestedItem}
                  // key is a reserved name in react and thus it is not passing this prop further
                  // so we need a key for this render method and a keyName to pass it down to the children
                  key={`${selectedRepo.nameWithOwner}-${suggestedItem.number}`}
                  keyName={`${selectedRepo.nameWithOwner}-${suggestedItem.number}`}
                  url={
                    suggestedItem.type === ItemType.PullRequest
                      ? `/${repoName}/pull/${suggestedItem.number}`
                      : `/${repoName}/issues/${suggestedItem.number}`
                  }
                />
              )
            })}
          </ul>
          <Text
            {...testIdProps('side-panel-suggested-items-footer')}
            sx={{color: 'fg.muted', display: 'block', textAlign: 'center', paddingTop: 4, paddingBottom: 4}}
            ref={searchResultsRef}
          >
            Showing {items?.length} most recent {items?.length === 1 ? 'item' : 'items'} that{' '}
            {items?.length === 1 ? 'has' : 'have'} not been added to this project
            {items && items?.length > 1 && '. Use search to narrow down this list.'}
          </Text>
        </div>
      ) : (
        <NoSuggestedRepos owner={owner} isOrganization={isOrganization} />
      )}
    </Box>
  )
})
