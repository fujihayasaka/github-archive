import type {SuppliedFilterProvider} from '@github-ui/filter'
import type {QuerySegment} from '@github-ui/filter-query'
import {validateQueryKeys} from '@github-ui/filter-query'
import {human} from '@github-ui/formatters'
import {ActionList, Heading} from '@primer/react'
import {AriaStatus} from '@primer/react/experimental'
import {useState} from 'react'

import {getBlankMessage, getResultsAnnouncement, ListMessage} from './components/ListMessage'
import {PartialResultsRow} from './components/PartialResultsRow'
import {PickerDialog} from './components/PickerDialog'
import {PickerHeaderContent} from './components/PickerHeaderContent'
import {useQuerySearch} from './hooks/use-query-search'
import type {DynamicProps, InnerDialogProps, IPickerItem, ItemLiterals} from './types'

interface DynamicPickerDialogProps<T extends IPickerItem>
  extends Omit<DynamicProps, 'providers'>,
    InnerDialogProps<T> {}

const noFilterLiterals = {
  title: 'No filter added',
  getDescription: (itemsName: string) => `Add a filter using the input to match ${itemsName}.`,
}

export function DynamicPickerDialog<T extends IPickerItem>({
  query: initialQuery = '',
  onSubmit,
  onDismiss,
  returnFocusRef,
  title,
  description,
  providers,
  warnIfUnsupportedProvider,
  itemConfig: {getSearchUrl, onRenderItemName, onRenderItemLeadingVisual, ...itemLiterals},
  onRenderFooterDetails,
}: DynamicPickerDialogProps<T>) {
  const {executedQuery, currentQuery, setCurrentQuery, setExecutedQuery, validationMessages} = useCurrentQuery({
    initialQuery,
    providers,
    warnIfUnsupportedProvider,
  })
  const results = useQuerySearch<T>({searchUrl: getSearchUrl(executedQuery), enabled: !!executedQuery})

  const items = executedQuery ? results.data?.items || [] : []
  const matchingItemsCount = executedQuery ? results.data?.totalCount || 0 : 0

  const blankMessage = getBlankMessage(results, items, itemLiterals)
  const blankState = executedQuery ? (
    blankMessage && <ListMessage>{blankMessage}</ListMessage>
  ) : (
    <NoFilterMessage {...itemLiterals} />
  )

  const messageToAnnounce = getDynamicResultsAnnouncement({
    executedQuery,
    blankMessage,
    visibleItemsCount: items.length,
    matchingItemsCount,
    itemLiterals,
  })

  const onApply = () => {
    onSubmit(currentQuery)
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
      onSubmit={onApply}
      returnFocusRef={returnFocusRef}
      renderHeader={({initialFocusRef, dialogLabelId, dialogDescriptionId}) => (
        <>
          <PickerHeaderContent
            dialogTitle={title}
            dialogLabelId={dialogLabelId}
            dialogDescription={description}
            dialogDescriptionId={dialogDescriptionId}
            inputLabel={`Filter ${itemLiterals.itemsName}`}
            inputRef={initialFocusRef}
            initialQuery={initialQuery}
            providers={providers}
            onDismiss={onDismiss}
            onQueryExecuted={setExecutedQuery}
            onQueryChange={setCurrentQuery}
            extraValidationMessages={validationMessages}
          />
          <ItemMatchCounter matchingItemsCount={matchingItemsCount} {...itemLiterals} />
          <AriaStatus announceOnShow className="sr-only">
            {messageToAnnounce}
          </AriaStatus>
        </>
      )}
      renderBody={() => (
        <PickerDialog.Body>
          {blankState || (
            <ActionList role="list" aria-label={itemLiterals.listTitle}>
              {items.map(item => (
                <ActionList.Item key={item.id} role="listitem">
                  {onRenderItemLeadingVisual && (
                    <ActionList.LeadingVisual>{onRenderItemLeadingVisual(item)}</ActionList.LeadingVisual>
                  )}
                  {onRenderItemName(item)}
                </ActionList.Item>
              ))}
            </ActionList>
          )}
          <PartialResultsRow itemCount={items.length} totalCount={matchingItemsCount} />
        </PickerDialog.Body>
      )}
      onRenderFooterDetails={onRenderFooterDetails}
    />
  )
}

interface UseQueryProps {
  initialQuery: string
  providers: SuppliedFilterProvider[]
  warnIfUnsupportedProvider?: boolean
}

function useCurrentQuery({initialQuery, providers, warnIfUnsupportedProvider}: UseQueryProps) {
  const [currentQuery, setCurrentQuery] = useState(initialQuery)
  const [executedQuery, setExecutedQuery] = useState(initialQuery)

  const [validationMessages, setValidationMessages] = useState<string[]>(() => {
    if (!warnIfUnsupportedProvider) return []
    return getFiltersInvalidMessage(validateQueryKeys(initialQuery, providers))
  })

  const onQueryExecuted = (newQuery: string) => {
    if (warnIfUnsupportedProvider && newQuery !== executedQuery) {
      setValidationMessages(getFiltersInvalidMessage(validateQueryKeys(newQuery, providers)))
    }

    setExecutedQuery(newQuery)
  }

  return {currentQuery, executedQuery, setCurrentQuery, setExecutedQuery: onQueryExecuted, validationMessages}
}

function ItemMatchCounter({
  matchingItemsCount,
  itemName,
  itemsName,
}: {
  matchingItemsCount: number
} & ItemLiterals) {
  return (
    <div className="px-3 py-2 color-fg-muted text-small color-bg-subtle border-bottom text-semibold">
      {human(matchingItemsCount)} {matchingItemsCount === 1 ? itemName : itemsName} matching
    </div>
  )
}

function NoFilterMessage({itemsName}: ItemLiterals) {
  return (
    <ListMessage>
      <Heading as="h2" variant="small">
        {noFilterLiterals.title}
      </Heading>
      <p className="color-fg-muted">{noFilterLiterals.getDescription(itemsName)}</p>
    </ListMessage>
  )
}

export function getFiltersInvalidMessage(invalidSegments: QuerySegment[]) {
  const invalidQualifiers = invalidSegments
    .filter(segment => segment.type === 'filter')
    .map(segment => segment.key)
    .sort()
  const hasFreeText = invalidSegments.some(segments => segments.type === 'text')

  const result = hasFreeText ? ['Free text is not supported.'] : []

  // eslint-disable-next-line github/unescaped-html-literal -- ValidationMessage will escape this safely
  return result.concat(invalidQualifiers.map(key => `<pre>${key}</pre> is not supported.`))
}

export function getDynamicResultsAnnouncement({
  executedQuery,
  blankMessage,
  matchingItemsCount,
  visibleItemsCount,
  itemLiterals,
}: {
  executedQuery: string
  blankMessage: string
  matchingItemsCount: number
  visibleItemsCount: number
  itemLiterals: ItemLiterals
}) {
  return executedQuery
    ? getResultsAnnouncement({
        blankMessage,
        totalItemsCount: matchingItemsCount,
        itemsCount: visibleItemsCount,
        itemLiterals,
      })
    : `${noFilterLiterals.title}. ${noFilterLiterals.getDescription(itemLiterals.itemsName)}`
}
