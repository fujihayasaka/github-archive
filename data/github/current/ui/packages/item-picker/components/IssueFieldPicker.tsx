/* eslint eslint-comments/no-use: off */

import {graphql, readInlineData, useRelayEnvironment, useFragment} from 'react-relay'

import {useCallback, useEffect, useMemo, useRef, useState, type RefObject} from 'react'
import {type ExtendedItemProps, ItemPicker} from '../components/ItemPicker'

import {LABELS} from '../constants/labels'
import {LazyItemPicker} from './LazyItemPicker'
import {clientSideRelayFetchQueryRetained} from '@github-ui/relay-environment'
import {IS_SERVER} from '@github-ui/ssr-utils'
import {useItemPickerErrorFallback} from '../hooks/useItemPickerErrorFallback'
import {ORGANIZATION_ISSUE_FIELDS_LIMIT} from '@github-ui/issue-types/constants.ts'
import type {IssueFieldPickerPaginated$key} from './__generated__/IssueFieldPickerPaginated.graphql'
import type {IssueFieldPickerQuery} from './__generated__/IssueFieldPickerQuery.graphql'
import type {
  IssueFieldPickerIssueField$data,
  IssueFieldPickerIssueField$key,
} from './__generated__/IssueFieldPickerIssueField.graphql'
import {createIssueFieldPickerItemLeadingVisual} from './IssueFieldLeadingVisual'

export const UNSET_ID = 'UNSET'

export const IssueFieldFragment = graphql`
  fragment IssueFieldPickerIssueField on IssueFields @inline {
    ... on IssueFieldText {
      id
      name
      dataType
    }
    ... on IssueFieldSingleSelect {
      id
      name
      dataType
    }
  }
`
export const IssueFieldPickerPaginatedFragment = graphql`
  fragment IssueFieldPickerPaginated on Organization @argumentDefinitions(issueFieldsPageSize: {type: "Int!"}) {
    issueFields(first: $issueFieldsPageSize) @connection(key: "Organization_issueFields") {
      edges {
        node {
          ...IssueFieldPickerIssueField
        }
      }
    }
  }
`

export const IssueFieldPickerGraphqlQuery = graphql`
  query IssueFieldPickerQuery($name: String!, $issueFieldsPageSize: Int!) {
    organization(login: $name) {
      ...IssueFieldPickerPaginated @arguments(issueFieldsPageSize: $issueFieldsPageSize)
    }
  }
`

export type IssueField = IssueFieldPickerIssueField$data

export type IssueFieldPickerProps = {
  title?: string
  width?: 'small' | 'medium' | 'large'
  issueId?: string
  owner: string
  fieldsSet: string[]
  readonly: boolean
  insidePortal?: boolean
  shortcutEnabled: boolean
  anchorElement: (props: React.HTMLAttributes<HTMLElement>, ref?: RefObject<HTMLButtonElement>) => JSX.Element
  onSelectionChange: (issueType: IssueField[]) => void
  onIssueUpdate?: () => void
  /**
   * Whether to render the issue type picker as a nested select panel (true) versus a standalone select
   * panel (false; default).
   */
  nested?: boolean
  ariaLabelledBy?: string
}

type ItemPickerWrapperProps = IssueFieldPickerProps & {
  fields: IssueFieldPickerPaginated$key | null
  isLoading: boolean
}

export function IssueFieldPicker({shortcutEnabled, anchorElement, ...props}: IssueFieldPickerProps) {
  return (
    // TODO
    // keybindingCommandId="item-pickers:open-issue-field"
    <LazyItemPicker
      anchorElement={anchorProps => anchorElement(anchorProps)}
      createChild={() => (
        <IssueFieldPickerFetcher
          anchorElement={anchorProps => anchorElement(anchorProps)}
          shortcutEnabled={shortcutEnabled}
          {...props}
        />
      )}
    />
  )
}

function IssueFieldPickerFetcher({owner, anchorElement, ...props}: IssueFieldPickerProps) {
  const environment = useRelayEnvironment()
  const [isLoading, setIsLoading] = useState(true)
  const [fetchKey, setFetchKey] = useState(0)
  const [isError, setIsError] = useState(false)
  const [data, setData] = useState<IssueFieldPickerPaginated$key | null>(null)

  useEffect(() => {
    if (!IS_SERVER) {
      clientSideRelayFetchQueryRetained<IssueFieldPickerQuery>({
        environment,
        query: IssueFieldPickerGraphqlQuery,
        variables: {name: owner, issueFieldsPageSize: ORGANIZATION_ISSUE_FIELDS_LIMIT},
      }).subscribe({
        next: internalData => {
          setData(internalData.organization ?? null)
          setIsLoading(false)
          setIsError(false)
        },
        error: () => {
          setIsError(true)
          setIsLoading(false)
        },
      })
    }
  }, [environment, fetchKey, owner])

  const {createFallbackComponent} = useItemPickerErrorFallback({
    errorMessage: LABELS.cantEditItems('fields'),
    anchorElement,
    open: true,
  })

  if (isError) {
    return createFallbackComponent(() => setFetchKey(current => current + 1))
  }

  return (
    <ItemPickerWrapper owner={owner} fields={data} isLoading={isLoading} anchorElement={anchorElement} {...props} />
  )
}

function ItemPickerWrapper({
  title = LABELS.fieldsHeader,
  width = 'medium',
  fields,
  fieldsSet,
  onSelectionChange,
  insidePortal,
  anchorElement,
  isLoading,
  nested,
}: ItemPickerWrapperProps) {
  const [filter, setFilter] = useState('')

  const data = useFragment<IssueFieldPickerPaginated$key>(IssueFieldPickerPaginatedFragment, fields)

  const fetchedIssueFields = useMemo(() => {
    const items =
      data?.issueFields?.edges?.flatMap(a =>
        // eslint-disable-next-line no-restricted-syntax
        a?.node ? [readInlineData<IssueFieldPickerIssueField$key>(IssueFieldFragment, a.node)] : [],
      ) || []

    return items.filter((issueField: IssueField) => {
      if (!issueField) return false
      if (fieldsSet.length > 0 && issueField.name) {
        return fieldsSet.indexOf(issueField.name) === -1
      }
      return true
    })
  }, [data, fieldsSet])

  const items = useMemo(() => {
    if (!filter) return fetchedIssueFields
    return fetchedIssueFields.filter(l => l.name && l.name.toLowerCase().indexOf(filter.toLowerCase()) >= 0)
  }, [fetchedIssueFields, filter])

  const filterItems = useCallback((value: string) => {
    setFilter(value)
  }, [])

  const getItemKey = useCallback((issueField: IssueField) => issueField.id || '', [])

  const convertToItemProps = useCallback((issueField: IssueField): ExtendedItemProps<IssueField> => {
    return {
      id: issueField.id,
      text: issueField.name,
      description: '',
      descriptionVariant: 'block',
      leadingVisual: createIssueFieldPickerItemLeadingVisual(issueField.dataType || 'TEXT'),
      source: issueField,
    }
  }, [])

  const anchorRef = useRef<HTMLButtonElement>(null)

  return (
    <ItemPicker
      loading={isLoading}
      items={items}
      initialSelectedItems={[]}
      filterItems={filterItems}
      title={title}
      getItemKey={getItemKey}
      convertToItemProps={convertToItemProps}
      placeholderText={`Filter fields`}
      selectionVariant="single"
      onSelectionChange={onSelectionChange}
      renderAnchor={anchorProps => anchorElement(anchorProps)}
      insidePortal={insidePortal}
      height={'large'}
      width={width}
      nested={nested}
      resultListAriaLabel={'Issue Fields results'}
      triggerOpen
      selectPanelRef={anchorRef}
    />
  )
}
