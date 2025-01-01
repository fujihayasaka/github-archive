/* eslint eslint-comments/no-use: off */
/* eslint-disable relay/unused-fields */
import type {
  IssueTypePickerIssueType$data,
  IssueTypePickerIssueType$key,
} from './__generated__/IssueTypePickerIssueType.graphql'
import {useAnalytics} from '@github-ui/use-analytics'
import {graphql, readInlineData, useRelayEnvironment, useFragment} from 'react-relay'
import type {IssueTypePickerQuery} from './__generated__/IssueTypePickerQuery.graphql'

import {forwardRef, useCallback, useEffect, useMemo, useState, type RefObject} from 'react'
import {IssueOpenedIcon, TriangleDownIcon} from '@primer/octicons-react'
import {type ExtendedItemProps, ItemPicker, type SharedBulkActionsItemPickerProps} from '../components/ItemPicker'

import type {IssueTypePickerPaginated$key} from './__generated__/IssueTypePickerPaginated.graphql'
import type {updateIssueIssueTypeBulkByQueryMutation$data} from '../mutations/__generated__/updateIssueIssueTypeBulkByQueryMutation.graphql'
import type {updateIssueIssueTypeBulkMutation$data} from '../mutations/__generated__/updateIssueIssueTypeBulkMutation.graphql'
import {commitUpdateIssueIssueTypeBulkByQueryMutation} from '../mutations/update-issue-issue-type-bulk-by-query-mutation'
import {commitUpdateIssueIssueTypeBulkMutation} from '../mutations/update-issue-issue-type-bulk-mutation'
import {Box, Button, Link} from '@primer/react'
import {LABELS} from '../constants/labels'
import {LazyItemPicker} from './LazyItemPicker'
import {clientSideRelayFetchQueryRetained} from '@github-ui/relay-environment'
import {IS_SERVER} from '@github-ui/ssr-utils'
import {useItemPickerErrorFallback} from '../hooks/useItemPickerErrorFallback'
import {createIssueTypePickerItemLeadingVisual} from './IssueTypePickerItemLeadingVisual'
import {SharedPicker} from './SharedPicker'
import {IssueTypeDot} from './IssueTypeDot'
import {SPECIAL_VALUES} from '../constants/placeholders'

export const UNSET_ID = 'UNSET'

export const IssueTypeFragment = graphql`
  fragment IssueTypePickerIssueType on IssueType @inline {
    id
    name
    isEnabled
    description
    color
  }
`

export const IssueTypePickerGraphqlQuery = graphql`
  query IssueTypePickerQuery($owner: String!, $repo: String!) {
    repository(owner: $owner, name: $repo) {
      ...IssueTypePickerPaginated
    }
  }
`

export type IssueType = IssueTypePickerIssueType$data

export type IssueTypePickerProps = {
  title?: string
  width?: 'small' | 'medium' | 'large'
  issueId?: string
  owner: string
  repo: string
  activeIssueType: IssueType | null
  preselectedIssueTypeName?: string
  showUnset?: boolean
  noTypeItem?: ExtendedItemProps<IssueTypePickerIssueType$data>
  readonly: boolean
  insidePortal?: boolean
  shortcutEnabled: boolean
  issueTypeToken?: string
  anchorElement: (props: React.HTMLAttributes<HTMLElement>, ref?: RefObject<HTMLButtonElement>) => JSX.Element
  onSelectionChange: (issueType: IssueType[]) => void
  onIssueUpdate?: () => void
  /**
   * Whether to render the issue type picker as a nested select panel (true) versus a standalone select
   * panel (false; default).
   */
  nested?: boolean
  ariaLabelledBy?: string
}

type ItemPickerWrapperProps = IssueTypePickerProps & {
  types: IssueTypePickerPaginated$key | null
  isLoading: boolean
}

export function IssueTypePicker({shortcutEnabled, anchorElement, ...props}: IssueTypePickerProps) {
  return (
    <LazyItemPicker
      keybindingCommandId="item-pickers:open-issue-type"
      anchorElement={anchorProps => anchorElement(anchorProps)}
      createChild={() => (
        <IssueTypePickerFetcher
          anchorElement={anchorProps => anchorElement(anchorProps)}
          shortcutEnabled={shortcutEnabled}
          {...props}
        />
      )}
    />
  )
}

function IssueTypePickerFetcher({owner, repo, anchorElement, ...props}: IssueTypePickerProps) {
  const environment = useRelayEnvironment()
  const [isLoading, setIsLoading] = useState(true)
  const [fetchKey, setFetchKey] = useState(0)
  const [isError, setIsError] = useState(false)
  const [data, setData] = useState<IssueTypePickerPaginated$key | null>(null)

  useEffect(() => {
    if (!IS_SERVER) {
      clientSideRelayFetchQueryRetained<IssueTypePickerQuery>({
        environment,
        query: IssueTypePickerGraphqlQuery,
        variables: {owner, repo},
      }).subscribe({
        next: internalData => {
          setData(internalData.repository ?? null)
          setIsLoading(false)
          setIsError(false)
        },
        error: () => {
          setIsError(true)
          setIsLoading(false)
        },
      })
    }
  }, [environment, fetchKey, owner, repo])

  const {createFallbackComponent} = useItemPickerErrorFallback({
    errorMessage: LABELS.cantEditItems('types'),
    anchorElement,
    open: true,
  })

  if (isError) {
    return createFallbackComponent(() => setFetchKey(current => current + 1))
  }

  return (
    <ItemPickerWrapper
      repo={repo}
      owner={owner}
      types={data}
      isLoading={isLoading}
      anchorElement={anchorElement}
      {...props}
    />
  )
}

function ItemPickerWrapper({
  title = LABELS.typesHeader,
  width = 'large',
  types,
  activeIssueType,
  showUnset = false,
  onSelectionChange,
  insidePortal,
  anchorElement,
  isLoading,
  nested,
  issueTypeToken,
  noTypeItem,
}: ItemPickerWrapperProps) {
  const [filter, setFilter] = useState('')

  const data = useFragment<IssueTypePickerPaginated$key>(
    graphql`
      fragment IssueTypePickerPaginated on Repository {
        issueTypes(first: 10) @connection(key: "Repository_issueTypes") {
          edges {
            node {
              ...IssueTypePickerIssueType
            }
          }
          totalCount
        }
      }
    `,
    types,
  )

  const fetchedIssueTypes = useMemo(
    () =>
      data?.issueTypes?.edges?.flatMap(a =>
        // eslint-disable-next-line no-restricted-syntax
        a?.node ? [readInlineData<IssueTypePickerIssueType$key>(IssueTypeFragment, a.node)] : [],
      ) || [],
    [data],
  )

  const issueTypeFromToken = useMemo(() => {
    // For types containing spaces, the type token will be surrounded by double quotes, but the types from the picker will be without quotes
    const formattedIssueTypeToken =
      issueTypeToken && issueTypeToken[0] === '"' && issueTypeToken[issueTypeToken.length - 1] === '"'
        ? issueTypeToken.slice(1, -1)
        : issueTypeToken

    return fetchedIssueTypes.find(issueType => issueType.name === formattedIssueTypeToken)
  }, [fetchedIssueTypes, issueTypeToken])

  const items = useMemo(() => {
    const repositoryIssueTypes = fetchedIssueTypes.slice().sort((a, b) => a.name.localeCompare(b.name))
    if (noTypeItem) {
      repositoryIssueTypes.unshift(SPECIAL_VALUES.noTypeData as IssueTypePickerIssueType$data)
    } else if (showUnset) {
      repositoryIssueTypes.unshift({
        id: UNSET_ID,
        name: 'No issue type',
        isEnabled: true,
        description: '',
        color: 'GRAY',
        ' $fragmentType': 'IssueTypePickerIssueType',
      })
    }
    if (!filter) return repositoryIssueTypes
    return repositoryIssueTypes.filter(l => l.name.toLowerCase().indexOf(filter.toLowerCase()) >= 0)
  }, [fetchedIssueTypes, filter, showUnset, noTypeItem])

  const filterItems = useCallback((value: string) => {
    setFilter(value)
  }, [])

  const getItemKey = useCallback((issueType: IssueType) => issueType.id, [])

  const convertToItemProps = useCallback((issueType: IssueType): ExtendedItemProps<IssueType> => {
    return {
      id: issueType.id,
      text: issueType.name,
      description: issueType.description ?? '',
      descriptionVariant: 'block',
      leadingVisual: createIssueTypePickerItemLeadingVisual(issueType.color),
      source: issueType,
    }
  }, [])

  const initialSelectedItems = useMemo(() => {
    if (noTypeItem?.selected) {
      return [SPECIAL_VALUES.noTypeData] as IssueTypePickerIssueType$data[]
    }
    if (activeIssueType) return [activeIssueType]
    if (issueTypeFromToken) return [issueTypeFromToken]
    return []
  }, [activeIssueType, issueTypeFromToken, noTypeItem])

  return (
    <ItemPicker
      loading={isLoading}
      items={items}
      initialSelectedItems={initialSelectedItems}
      filterItems={filterItems}
      title={title}
      subtitle={
        <>
          {LABELS.typesSubHeader} <Link href="https://gh.io/issue-types-feedback">{LABELS.feedback}</Link>
        </>
      }
      getItemKey={getItemKey}
      convertToItemProps={convertToItemProps}
      placeholderText={`Filter types`}
      selectionVariant="single"
      onSelectionChange={onSelectionChange}
      renderAnchor={anchorProps => anchorElement(anchorProps)}
      insidePortal={insidePortal}
      height={'large'}
      width={width}
      nested={nested}
      resultListAriaLabel={'Issue Type results'}
      triggerOpen
      keybindingCommandId="item-pickers:open-issue-type"
    />
  )
}

type BulkIssueIssueTypePickerProps = Omit<IssueTypePickerProps, 'issueId' | 'onSelectionChange'> &
  SharedBulkActionsItemPickerProps

export function BulkIssueIssueTypePicker({
  onError,
  onCompleted,
  issuesToActOn,
  useQueryForAction,
  repositoryId,
  query,
  activeIssueType,
  ...rest
}: BulkIssueIssueTypePickerProps) {
  const environment = useRelayEnvironment()
  const {sendAnalyticsEvent} = useAnalytics()
  const onSelectionChange = useCallback(
    (selectedIssueType: IssueType[]) => {
      const issueTypeId = selectedIssueType.length === 1 ? selectedIssueType[0]?.id : null
      if (!issueTypeId || issueTypeId === activeIssueType?.id) return
      const mutationArgs = {
        environment,
        onError: (error: Error) => {
          onError?.(error)
        },
      }

      sendAnalyticsEvent('issues_index.bulk_action_issue_type', 'BULK_ISSUE_ISSUE_TYPE_PICKER', {
        initialIssueTypeId: activeIssueType?.id ?? '',
        issueTypeId: issueTypeId === 'UNSET' ? '' : issueTypeId ?? '',
        issueIds: [...issuesToActOn],
      })

      if (useQueryForAction && repositoryId && query) {
        commitUpdateIssueIssueTypeBulkByQueryMutation({
          ...mutationArgs,
          input: {
            repositoryId,
            query,
            issueTypeId,
          },
          optimisticUpdateIds: issuesToActOn,
          onCompleted: ({updateIssuesBulkByQuery}: updateIssueIssueTypeBulkByQueryMutation$data) => {
            onCompleted?.(updateIssuesBulkByQuery?.jobId || undefined)
          },
        })
      } else {
        commitUpdateIssueIssueTypeBulkMutation({
          ...mutationArgs,
          input: {
            ids: [...issuesToActOn],
            issueTypeId,
          },
          onCompleted: ({updateIssuesBulk}: updateIssueIssueTypeBulkMutation$data) => {
            onCompleted?.(updateIssuesBulk?.jobId || undefined)
          },
        })
      }
    },
    [
      activeIssueType?.id,
      environment,
      issuesToActOn,
      onCompleted,
      onError,
      query,
      repositoryId,
      sendAnalyticsEvent,
      useQueryForAction,
    ],
  )
  return <IssueTypePicker {...rest} onSelectionChange={onSelectionChange} showUnset activeIssueType={activeIssueType} />
}

export function DefaultIssueTypeAnchor({
  activeIssueType,
  ariaLabelledBy,
  readonly,
  anchorProps,
  preselectedIssueTypeName,
}: Pick<IssueTypePickerProps, 'activeIssueType' | 'ariaLabelledBy' | 'readonly' | 'preselectedIssueTypeName'> & {
  anchorProps?: React.HTMLAttributes<HTMLElement> | undefined
}) {
  const selectedType = getDefaultIssueTypeAnchorLabel(activeIssueType, preselectedIssueTypeName)

  return (
    <Button
      {...anchorProps}
      trailingVisual={readonly ? null : TriangleDownIcon}
      aria-labelledby={ariaLabelledBy}
      disabled={readonly}
      sx={{width: '160px'}}
    >
      {/* calculated in a way so that the whole container is 160px wide */}
      <Box className="css-truncate css-truncate-target" sx={{width: '110px', textAlign: 'left'}}>
        {selectedType}
      </Box>
    </Button>
  )
}

const getDefaultIssueTypeAnchorLabel = (
  activeIssueType: IssueType | null,
  preselectedIssueTypeName?: string,
): string => {
  if (activeIssueType) return activeIssueType.name
  if (preselectedIssueTypeName) return preselectedIssueTypeName
  return 'None'
}

type DefaultIssueTypePickerFooterAnchorProps = Pick<IssueTypePickerProps, 'activeIssueType' | 'readonly'> & {
  anchorProps?: React.HTMLAttributes<HTMLElement> | undefined
}

export const DefaultIssueTypePickerFooterAnchor = forwardRef<
  HTMLButtonElement,
  DefaultIssueTypePickerFooterAnchorProps
>(({activeIssueType, readonly, anchorProps}, ref) => {
  return (
    <SharedPicker
      anchorText={LABELS.noIssueTypes}
      sharedPickerMainValue={activeIssueType?.name}
      anchorProps={readonly ? undefined : anchorProps}
      ariaLabel={LABELS.selectIssueTypes}
      readonly={readonly}
      leadingIcon={IssueOpenedIcon}
      hotKey={undefined}
      ref={ref}
      leadingIconElement={activeIssueType && <IssueTypeDot color={activeIssueType.color} />}
    />
  )
})

DefaultIssueTypePickerFooterAnchor.displayName = 'DefaultIssueTypePickerFooterAnchor'
