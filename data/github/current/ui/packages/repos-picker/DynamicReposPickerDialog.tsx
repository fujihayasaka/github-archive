import {human} from '@github-ui/formatters'
import {ActionList, Heading} from '@primer/react'
import {useState} from 'react'

import {ListItemRepoIcon} from './components/ListItemRepoIcon'
import {getBlankMessage, ListMessage} from './components/ListMessage'
import {PartialResultsRow} from './components/PartialResultsRow'
import {PickerDialog} from './components/PickerDialog'
import {ReposPickerHeaderContent} from './components/ReposPickerHeaderContent'
import {useQueryRepositories} from './hooks/use-query-repositories'
import type {CommonDialogProps, DynamicMatchingProps} from './types'

type ReposPickerDialogProps = DynamicMatchingProps & CommonDialogProps

export function DynamicReposPickerDialog({
  orgLogin,
  query: initialQuery = '',
  onSubmit,
  onDismiss,
  returnFocusRef,
  allowedProviders,
}: ReposPickerDialogProps) {
  const [query, setQuery] = useState<string>(initialQuery)
  const results = useQueryRepositories({orgLogin, query, enabled: !!query})

  const items = query ? results.data?.repositories || [] : []
  const matchingItemsCount = query ? results.data?.repositoryCount || 0 : 0

  const blankMessage = getBlankMessage(results, items)
  const blankState = query ? blankMessage && <ListMessage>{blankMessage}</ListMessage> : <NoFilterMessage />

  const onApply = () => {
    onSubmit(query)
    onDismiss()
  }

  return (
    <PickerDialog
      onClose={onDismiss}
      footerButtons={[
        {
          onClick: onDismiss,
          content: 'Cancel',
        },
        {
          buttonType: 'primary',
          onClick: onApply,
          content: 'Apply',
        },
      ]}
      returnFocusRef={returnFocusRef}
      renderHeader={({initialFocusRef}) => (
        <>
          <ReposPickerHeaderContent
            dialogTitle="Filter"
            inputRef={initialFocusRef}
            initialQuery={initialQuery}
            orgLogin={orgLogin}
            allowedProviders={allowedProviders}
            onDismiss={onDismiss}
            setQuery={setQuery}
          />
          <ItemMatchCounter matchingItemsCount={matchingItemsCount} />
        </>
      )}
      renderBody={() => (
        <PickerDialog.Body>
          {blankState || (
            <ActionList role="list" aria-label="Repository List">
              {items.map(repo => (
                <ActionList.Item key={repo.id} role="listitem">
                  <ActionList.LeadingVisual>
                    <ListItemRepoIcon visibility={repo.visibility} />
                  </ActionList.LeadingVisual>
                  {repo.name}
                </ActionList.Item>
              ))}
            </ActionList>
          )}
          <PartialResultsRow itemCount={items.length} totalCount={results.data?.repositoryCount || 0} />
        </PickerDialog.Body>
      )}
    />
  )
}

function ItemMatchCounter({matchingItemsCount}: {matchingItemsCount: number}) {
  return (
    <div className="px-3 py-2 color-fg-muted text-small color-bg-subtle border-bottom text-semibold">
      {human(matchingItemsCount)} {matchingItemsCount === 1 ? 'repository' : 'repositories'} matching
    </div>
  )
}

function NoFilterMessage() {
  return (
    <ListMessage>
      <Heading as="h3" variant="small">
        No filter added
      </Heading>
      <p className="color-fg-muted">Add a filter using the input to match repositories.</p>
    </ListMessage>
  )
}
