import {debounce} from '@github/mini-throttle'
import type {RepoData} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {ListView} from '@github-ui/list-view'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ListItem} from '@github-ui/list-view/ListItem'
import {useRepositoryItems} from '@github-ui/use-repository-items'
import {SearchIcon} from '@primer/octicons-react'
import {Spinner, TextInput, Button} from '@primer/react'
import {Blankslate, Dialog} from '@primer/react/experimental'
import {useCallback, useState, useMemo, useEffect} from 'react'
import {pluralizeRepositories, pluralizeResults} from '../../utils/pluralize'
import {useDelayedLoading} from '../../utils/use-delayed-loading'

import styles from './RepoSelectionDialog.module.css'

export interface RepoSelectionDialogProps {
  initialFilterText?: string
  // If provided, repos owned by this user login will be sorted to the top
  prefferedUserLogin?: string
  onClose: (selectedItems: RepoData[]) => void
  initialSelectedItems: RepoData[]
  // Allows for modification of the user's query prior to hitting the API. ex. adding org:<org> to get only <org>'s repos
  isOpen: boolean
}

interface LoadMoreProps {
  currentCount: number
  totalCount: number
  loadMore: (endCursor: string, afterFetch: () => void) => void
  loading: boolean
  endCursor: string | null
}

export const DIALOG_LABEL = 'Add repositories'

/**
 * This is the dialog used to select repositories for inclusion in a docset.
 */
export function RepoSelectionDialog({
  initialFilterText = '',
  prefferedUserLogin = '',
  initialSelectedItems,
  isOpen,
  onClose,
}: RepoSelectionDialogProps) {
  // Reusing filterText to query repos causes the value in the TextInput to not update until debouncedSetFilter runs so we are using 2 separate states
  const [filterText, setFilterText] = useState(initialFilterText)
  const [filterQuery, setFilterQuery] = useState(initialFilterText)
  // Don't send off new filter queries if the user is typing
  const debouncedSetFilter = useMemo(() => debounce((newFilter: string) => setFilterQuery(newFilter), 400), [])
  const {repositories, loading, totalCount, loadMore, endCursor} = useRepositoryItems(filterQuery)
  const [selectedItems, setSelectedItems] = useState<RepoData[]>([])
  const isLoading = useDelayedLoading(loading)
  const onSelected = useCallback((item: RepoData, isSelected: boolean) => {
    if (isSelected) {
      setSelectedItems(items => [...items, item])
    } else {
      setSelectedItems(items => items.filter(i => i.nameWithOwner !== item.nameWithOwner))
    }
  }, [])
  const setFilterTextAndQuery = useCallback(
    (newFilter: string) => {
      setFilterText(newFilter)
      debouncedSetFilter(newFilter)
    },
    [debouncedSetFilter],
  )
  const onCancel = useCallback(() => {
    setSelectedItems([])
    setFilterTextAndQuery(initialFilterText)
    onClose(initialSelectedItems)
  }, [setFilterTextAndQuery, initialFilterText, onClose, initialSelectedItems])
  const onOk = useCallback(() => {
    setSelectedItems([])
    setFilterTextAndQuery(initialFilterText)
    onClose([...initialSelectedItems, ...selectedItems])
  }, [setFilterTextAndQuery, initialFilterText, onClose, initialSelectedItems, selectedItems])
  if (!isOpen) {
    return null
  }

  return (
    <Dialog
      footerButtons={[
        {buttonType: 'normal', content: 'Cancel', onClick: onCancel},
        {buttonType: 'primary', content: 'Apply', onClick: onOk},
      ]}
      renderFooter={({footerButtons}) => {
        return (
          <Dialog.Footer className={styles.Dialog_Footer}>
            <span>{pluralizeRepositories(selectedItems.length)} selected</span>
            {footerButtons && (
              <div className={styles.Box}>
                <Dialog.Buttons buttons={footerButtons} />
              </div>
            )}
          </Dialog.Footer>
        )
      }}
      onClose={onCancel}
      title={DIALOG_LABEL}
      renderBody={() => (
        <Dialog.Body className={styles.Dialog_Body}>
          <TextInput
            leadingVisual={SearchIcon}
            placeholder="Search repositories"
            onChange={e => setFilterTextAndQuery(e.target.value)}
            value={filterText}
            aria-label="Search repositories"
            loaderPosition="trailing"
            className={styles.TextInput}
          />
          {isLoading ? (
            <Blankslate>
              <Spinner aria-label="Loading" />
            </Blankslate>
          ) : repositories.length === 0 ? (
            <Blankslate>No results found.</Blankslate>
          ) : (
            <div>
              <ListView isSelectable title="Repositories" variant="compact">
                {repositories
                  .filter(repo => !initialSelectedItems.map(r => r.nameWithOwner).includes(repo.nameWithOwner))
                  // sort repositories owned by the current org first
                  .sort(
                    (a, b) =>
                      ((b.owner.login === prefferedUserLogin) as unknown as number) -
                      ((a.owner.login === prefferedUserLogin) as unknown as number),
                  )
                  .map(repo => (
                    <ListItem
                      key={repo.name}
                      isSelected={selectedItems.some(i => i.nameWithOwner === repo.nameWithOwner)}
                      onSelect={isSelected => onSelected(repo, isSelected)}
                      title={<ListItemTitle value={repo.nameWithOwner} />}
                      className={styles.ListItem_0}
                    >
                      <ListItemLeadingContent className={styles.ListItemLeadingContent_0}>
                        <GitHubAvatar src={repo.owner.avatarUrl} square={repo.isInOrganization} size={16} />
                      </ListItemLeadingContent>
                    </ListItem>
                  ))}
                <LoadMore
                  currentCount={repositories.length}
                  totalCount={totalCount}
                  loadMore={loadMore}
                  loading={loading}
                  endCursor={endCursor}
                />
              </ListView>
            </div>
          )}
          <span role="status" className="sr-only">
            {pluralizeResults(repositories.length)} returned.
          </span>
        </Dialog.Body>
      )}
      className={styles.Dialog}
    />
  )
}

const LoadMore = ({currentCount, totalCount, loadMore, loading, endCursor}: LoadMoreProps) => {
  const [isLoadingMore, setIsLoadingMore] = useState(false)

  const handleLoadMore = useCallback(() => {
    if (endCursor === null) {
      return
    }
    setIsLoadingMore(true)
    loadMore(endCursor, () => setIsLoadingMore(false))
  }, [loadMore, endCursor])

  useEffect(() => {
    if (!loading) {
      setIsLoadingMore(false)
    }
  }, [loading])

  const content = useMemo(() => {
    if (isLoadingMore) {
      return (
        <div className={styles.Box_1}>
          <Spinner aria-label="Loading" />
        </div>
      )
    }

    return (
      <Button variant="invisible" onClick={handleLoadMore}>
        Load more
      </Button>
    )
  }, [isLoadingMore, handleLoadMore])

  if (currentCount >= totalCount) {
    return null
  }

  return (
    <div role="listitem" tabIndex={-1} className={styles.Box_2}>
      {content}
    </div>
  )
}
