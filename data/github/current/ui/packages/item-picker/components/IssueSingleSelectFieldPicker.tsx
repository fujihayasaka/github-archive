/* eslint eslint-comments/no-use: off */

import {graphql, readInlineData, useRelayEnvironment} from 'react-relay'

import {useCallback, useEffect, useMemo, useRef, useState, type RefObject} from 'react'
import {type ExtendedItemProps, ItemPicker} from '../components/ItemPicker'

import {LABELS} from '../constants/labels'
import {LazyItemPicker} from './LazyItemPicker'
import {clientSideRelayFetchQueryRetained} from '@github-ui/relay-environment'
import {IS_SERVER} from '@github-ui/ssr-utils'
import {useItemPickerErrorFallback} from '../hooks/useItemPickerErrorFallback'
import type {
  IssueSingleSelectFieldPickerOption$data,
  IssueSingleSelectFieldPickerOption$key,
} from './__generated__/IssueSingleSelectFieldPickerOption.graphql'
import type {IssueSingleSelectFieldPickerFieldQuery} from './__generated__/IssueSingleSelectFieldPickerFieldQuery.graphql'
import {createIssueSingleSelectFieldPickerItemLeadingVisual} from './IssueFieldLeadingVisual'

export const UNSET_ID = 'UNSET'

const IssueSingleSelectFieldPickerOptionFragment = graphql`
  fragment IssueSingleSelectFieldPickerOption on IssueFieldSingleSelectOption @inline {
    ... on IssueFieldSingleSelectOption {
      id
      name
      description
      color
    }
  }
`

export const IssueSingleSelectFieldPickerFieldGraphqlQuery = graphql`
  query IssueSingleSelectFieldPickerFieldQuery($id: ID!) {
    node(id: $id) {
      ... on IssueFieldSingleSelect {
        options {
          ...IssueSingleSelectFieldPickerOption
        }
      }
    }
  }
`

export type IssueFieldSingleSelectOption = IssueSingleSelectFieldPickerOption$data

export type IssueSingleSelectFieldPickerProps = {
  title?: string
  width?: 'small' | 'medium' | 'large'
  fieldId: string
  selectedOption: string | null
  readonly: boolean
  insidePortal?: boolean
  shortcutEnabled: boolean
  anchorElement: (props: React.HTMLAttributes<HTMLElement>, ref?: RefObject<HTMLButtonElement>) => JSX.Element
  onSelectionChange: (selectedOption: IssueFieldSingleSelectOption | null) => void
  onIssueUpdate?: () => void
  /**
   * Whether to render the issue type picker as a nested select panel (true) versus a standalone select
   * panel (false; default).
   */
  nested?: boolean
  ariaLabelledBy?: string
  /**
   * Whether this panel is lazily loaded, when the anchor element is clicked. When set to false, the
   * panel will be loaded immediately. This is used when we want to immediately select an option
   * after picking a single select field.
   */
  isLazy: boolean
}

type ItemPickerWrapperProps = Omit<IssueSingleSelectFieldPickerProps, 'isLazy'> & {
  values: IssueSingleSelectFieldPickerOption$key[]
  isLoading: boolean
}

export function IssueSingleSelectFieldPicker({
  shortcutEnabled,
  anchorElement,
  isLazy,
  ...props
}: IssueSingleSelectFieldPickerProps) {
  if (isLazy) {
    return (
      // TODO
      // keybindingCommandId="item-pickers:open-issue-field"
      <LazyItemPicker
        anchorElement={anchorProps => anchorElement(anchorProps)}
        createChild={() => (
          <IssueSingleSelectFieldPickerFetcher
            anchorElement={anchorProps => anchorElement(anchorProps)}
            shortcutEnabled={shortcutEnabled}
            {...props}
          />
        )}
      />
    )
  } else {
    return (
      <IssueSingleSelectFieldPickerFetcher
        anchorElement={anchorProps => anchorElement(anchorProps)}
        shortcutEnabled={shortcutEnabled}
        {...props}
      />
    )
  }
}

function IssueSingleSelectFieldPickerFetcher({
  fieldId,
  anchorElement,
  ...props
}: Omit<IssueSingleSelectFieldPickerProps, 'isLazy'>) {
  const environment = useRelayEnvironment()
  const [isLoading, setIsLoading] = useState(true)
  const [fetchKey, setFetchKey] = useState(0)
  const [isError, setIsError] = useState(false)
  const [data, setData] = useState<IssueSingleSelectFieldPickerOption$key[]>([])

  useEffect(() => {
    if (!IS_SERVER) {
      clientSideRelayFetchQueryRetained<IssueSingleSelectFieldPickerFieldQuery>({
        environment,
        query: IssueSingleSelectFieldPickerFieldGraphqlQuery,
        variables: {id: fieldId},
      }).subscribe({
        next: internalData => {
          const keys = internalData.node?.options as IssueSingleSelectFieldPickerOption$key[]
          setData(keys ?? [])
          setIsLoading(false)
          setIsError(false)
        },
        error: () => {
          setIsError(true)
          setIsLoading(false)
        },
      })
    }
  }, [environment, fetchKey, fieldId])

  const {createFallbackComponent} = useItemPickerErrorFallback({
    errorMessage: LABELS.cantEditItems('fields'),
    anchorElement,
    open: true,
  })

  if (isError) {
    return createFallbackComponent(() => setFetchKey(current => current + 1))
  }

  return (
    <ItemPickerWrapper fieldId={fieldId} values={data} isLoading={isLoading} anchorElement={anchorElement} {...props} />
  )
}

function ItemPickerWrapper({
  title = LABELS.fieldSingleSelectHeader,
  width = 'medium',
  values,
  selectedOption,
  onSelectionChange,
  insidePortal,
  anchorElement,
  isLoading,
}: ItemPickerWrapperProps) {
  const [filter, setFilter] = useState('')

  const fetchedIssueFieldOptions = values.flatMap(a =>
    // eslint-disable-next-line no-restricted-syntax
    a ? [readInlineData<IssueSingleSelectFieldPickerOption$key>(IssueSingleSelectFieldPickerOptionFragment, a)] : [],
  )

  const items = useMemo(() => {
    if (!filter) return fetchedIssueFieldOptions
    return fetchedIssueFieldOptions.filter(l => l.name && l.name.toLowerCase().indexOf(filter.toLowerCase()) >= 0)
  }, [fetchedIssueFieldOptions, filter])

  const filterItems = useCallback((value: string) => {
    setFilter(value)
  }, [])

  const getItemKey = useCallback((option: IssueFieldSingleSelectOption) => option.id || '', [])

  const convertToItemProps = useCallback(
    (option: IssueFieldSingleSelectOption): ExtendedItemProps<IssueFieldSingleSelectOption> => {
      return {
        id: option.id,
        text: option.name,
        description: option.description || '',
        descriptionVariant: 'block',
        leadingVisual: createIssueSingleSelectFieldPickerItemLeadingVisual(option.color),
        source: option,
      }
    },
    [],
  )

  const initialSelectedItems = useMemo(() => {
    if (selectedOption) {
      const selectedItem = fetchedIssueFieldOptions.find(item => item.name === selectedOption)
      if (selectedItem) {
        return [selectedItem]
      }
    }
    return []
  }, [fetchedIssueFieldOptions, selectedOption])

  const anchorRef = useRef<HTMLButtonElement>(null)
  return (
    <ItemPicker
      loading={isLoading}
      items={items}
      initialSelectedItems={initialSelectedItems}
      filterItems={filterItems}
      title={title}
      getItemKey={getItemKey}
      convertToItemProps={convertToItemProps}
      placeholderText={`Filter option`}
      selectionVariant="single"
      onSelectionChange={selectedItems =>
        onSelectionChange(selectedItems && selectedItems.length > 0 && selectedItems[0] ? selectedItems[0] : null)
      }
      renderAnchor={anchorProps => anchorElement(anchorProps)}
      insidePortal={insidePortal}
      height={'large'}
      width={width}
      resultListAriaLabel={'Issue field option results'}
      triggerOpen
      selectPanelRef={anchorRef}
    />
  )
}
