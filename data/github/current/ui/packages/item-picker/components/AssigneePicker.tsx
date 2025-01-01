import {GitHubAvatar} from '@github-ui/github-avatar'
import {CopilotIcon} from '@primer/octicons-react'
import {useDebounce} from '@github-ui/use-debounce'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {Box, Label} from '@primer/react'
import type React from 'react'
import {fetchQuery, graphql, readInlineData, useRelayEnvironment} from 'react-relay'
import {useCallback, useEffect, useMemo, useRef, useState, type RefObject} from 'react'
import {Banner} from '@primer/react/experimental'

import {clientSideRelayFetchQueryRetained} from '@github-ui/relay-environment'
import {ERRORS} from '../constants/errors'
import {LABELS} from '../constants/labels'
import {commitUpdateIssueAssigneesBulkMutation} from '../mutations/update-issue-assignees-bulk-mutation'
import type {
  AssigneePickerSearchAssignableRepositoryUsersQuery,
  AssigneePickerSearchAssignableRepositoryUsersQuery$data,
} from './__generated__/AssigneePickerSearchAssignableRepositoryUsersQuery.graphql'
import type {
  AssigneePickerSearchAssignableUsersQuery,
  AssigneePickerSearchAssignableUsersQuery$data,
} from './__generated__/AssigneePickerSearchAssignableUsersQuery.graphql'
import {type ExtendedItemProps, ItemPicker, type SharedBulkActionsItemPickerProps} from './ItemPicker'
import type {ItemGroup} from '../shared'
import type {updateIssueAssigneesBulkMutation$data} from '../mutations/__generated__/updateIssueAssigneesBulkMutation.graphql'
import {commitUpdateIssueAssigneesBulkByQueryMutation} from '../mutations/update-issue-assignees-bulk-by-query-mutation'
import type {updateIssueAssigneesBulkByQueryMutation$data} from '../mutations/__generated__/updateIssueAssigneesBulkByQueryMutation.graphql'
import {assigneesGroup, getGroupItemId, sortAssigneePickerUsers, suggestionsGroup} from './AssigneePickerUtils'
import {VALUES} from '../constants/values'
import {IS_SERVER} from '@github-ui/ssr-utils'
import {LazyItemPicker} from './LazyItemPicker'

import {SPECIAL_VALUES} from '../constants/placeholders'
import {fuzzyFilter} from '@github-ui/fuzzy-score/fuzzy-filter'
import {hasFuzzyMatch} from '@github-ui/fuzzy-score/has-fuzzy-match'
import assigneePickerStyles from './AssigneePicker.module.css'
import {useViewer} from '../hooks/useViewer'
import {CopilotAvatar} from '@github-ui/copilot-avatar'

import {getActorCapabilities} from '../utils/assignee-picker'
import type {
  AssigneePickerAssignee$key,
  AssigneePickerAssignee$data,
} from './__generated__/AssigneePickerAssignee.graphql'
import {isFeatureEnabled} from '@github-ui/feature-flags'
export type Assignee = Omit<AssigneePickerAssignee$data, ' $fragmentType'> & {type?: string}

type Name = 'assignee' | 'author'

export type AssigneePickerProps = {
  repo: string
  owner: string
  readonly: boolean
  /** An optional data set to be used when the picker is first opened. If this data is not provided, a loading state
   * is shown in the picker and the data is loaded on demand.
   */
  suggestions?: Assignee[]
  assignees: Assignee[]
  insidePortal?: boolean
  shortcutEnabled: boolean
  noAssigneeOption?: ExtendedItemProps<Assignee>
  selectionVariant?: 'single' | 'multiple'
  anchorElement: (props: React.HTMLAttributes<HTMLElement>, ref: RefObject<HTMLButtonElement>) => JSX.Element
  onSelectionChange: (selectedAssignees: Assignee[]) => void
  /**
   * Whether to render the assignee picker as a nested select panel (true) versus a standalone select
   * panel (false; default).
   */
  nested?: boolean
  triggerOpen?: boolean
  title?: string
  name?: Name
  maximumAssignees?: number
  showNoMatchItem?: boolean
}

export type AssigneeIssuePickerProps = AssigneePickerProps & {
  number: number
}

export type AssigneeRepositoryPickerProps = AssigneePickerProps & {
  assigneeTokens: string[]
  includeAssignableBots: boolean
  includeAuthorableBots: boolean
}

type ItemPickerWrapperProps = AssigneePickerProps & {
  searchAssignees: (query: string) => Promise<Assignee[]> | Assignee[]
  isLoading?: boolean
  suggestions: Assignee[]
}

type BulkAssigneePickerProps = Omit<AssigneePickerProps, 'id' | 'assignees' | 'onSelectionChange'> & {
  assigneesAppliedToAll: Assignee[]
  assigneesAppliedToSome: Assignee[]
  existingIssueAssignees: Map<string, string[]>
  connectionIds: {[key: string]: string[]}
} & SharedBulkActionsItemPickerProps

// note: when the query variable is empty, this the suggestedAssignees resolvers is returning the participants
export const SearchAssignableUsersQuery = graphql`
  query AssigneePickerSearchAssignableUsersQuery(
    $owner: String!
    $name: String!
    $number: Int!
    $query: String!
    $first: Int!
  ) {
    repository(owner: $owner, name: $name) {
      issueOrPullRequest(number: $number) {
        ... on Assignable {
          suggestedActors(first: $first, query: $query) {
            nodes {
              ...AssigneePickerAssignee @dangerously_unaliased_fixme
            }
          }
        }
      }
    }
  }
`

export const SearchAssignableRepositoryUsers = graphql`
  query AssigneePickerSearchAssignableRepositoryUsersQuery(
    $owner: String!
    $name: String!
    $query: String
    $loginNames: String
    $first: Int!
    $capabilities: [RepositorySuggestedActorFilter!]!
  ) {
    repository(owner: $owner, name: $name) {
      suggestedActors(first: $first, query: $query, loginNames: $loginNames, capabilities: $capabilities) {
        nodes {
          ...AssigneePickerAssignee
        }
        totalCount
      }
    }
  }
`

export const AssigneeFragment = graphql`
  fragment AssigneePickerAssignee on Actor @inline {
    __typename
    id
    login
    name
    # eslint-disable-next-line relay/unused-fields
    profileResourcePath
    avatarUrl(size: 64)
    ... on Bot {
      # This fragment is used in several places. Despite this field not being used here, we rely on it in other files.
      # eslint-disable-next-line relay/unused-fields
      isCopilot
    }
  }
`

export function AssigneePicker({anchorElement, shortcutEnabled, ...props}: AssigneeIssuePickerProps) {
  return (
    <LazyItemPicker
      anchorElement={(anchorProps, ref) => anchorElement(anchorProps, ref)}
      createChild={() => (
        <AssigneePickerInternal
          anchorElement={(ref, anchorProps) => anchorElement(ref, anchorProps)}
          shortcutEnabled={shortcutEnabled}
          triggerOpen
          {...props}
        />
      )}
      insidePortal={props.insidePortal}
      keybindingCommandId={getKeyBindingCommandId(props.name)}
    />
  )
}

export function AssigneeRepositoryPicker({shortcutEnabled, anchorElement, ...props}: AssigneeRepositoryPickerProps) {
  return (
    <LazyItemPicker
      anchorElement={(anchorProps, ref) => anchorElement(anchorProps, ref)}
      keybindingCommandId={getKeyBindingCommandId(props.name)}
      createChild={() => (
        <AssigneeRepositoryPickerInternal
          shortcutEnabled={shortcutEnabled}
          anchorElement={anchorElement}
          triggerOpen
          {...props}
        />
      )}
    />
  )
}

function AssigneeRepositoryPickerInternal({
  repo,
  owner,
  assignees,
  assigneeTokens,
  suggestions,
  maximumAssignees,
  includeAssignableBots,
  includeAuthorableBots,
  ...props
}: AssigneeRepositoryPickerProps & {assigneeTokens: string[]}) {
  const environment = useRelayEnvironment()
  const [isLoading, setIsLoading] = useState(false)
  const [data, setData] = useState<AssigneePickerSearchAssignableRepositoryUsersQuery$data | null>(null)
  const [suggestedAssignees, setSuggestedAssignees] = useState<Assignee[] | null>(null)
  const [totalAssignableUsers, setTotalAssignableUsers] = useState<number | null>(null)

  const capabilities = useMemo(
    () => getActorCapabilities({includeAssignableBots, includeAuthorableBots}),
    [includeAssignableBots, includeAuthorableBots],
  )

  const shouldFetchFromAssigneeTokens = assigneeTokens.length > 0
  useEffect(() => {
    if (!IS_SERVER && shouldFetchFromAssigneeTokens) {
      setIsLoading(true)
      clientSideRelayFetchQueryRetained<AssigneePickerSearchAssignableRepositoryUsersQuery>({
        environment,
        query: SearchAssignableRepositoryUsers,
        variables: {
          owner,
          name: repo,
          loginNames: assigneeTokens.join(','),
          first: assigneeTokens.length,
          capabilities,
        },
      }).subscribe({
        next: internalData => {
          setData(internalData ?? null)
          setIsLoading(false)
        },
        error: () => {
          setIsLoading(false)
        },
      })
    }
  }, [
    environment,
    owner,
    repo,
    assigneeTokens,
    includeAssignableBots,
    includeAuthorableBots,
    capabilities,
    shouldFetchFromAssigneeTokens,
  ])

  const searchAssignees = useCallback(
    (query: string) => {
      if (totalAssignableUsers && totalAssignableUsers <= VALUES.maximumSuggestedUsers && suggestedAssignees) {
        setIsLoading(false)
        return fuzzyFilter<Assignee>({
          items: [
            ...suggestedAssignees,
            ...(props.noAssigneeOption ? [SPECIAL_VALUES.noAssigneeData as Assignee] : []),
          ],
          filter: query,
          key: (l: Assignee) => l.login || (props.noAssigneeOption?.source?.login ?? ''),
          secondaryKey: (l: Assignee) => `${l.name}`,
        })
      }

      return new Promise<Assignee[]>((resolve, reject) => {
        setIsLoading(true)
        fetchQuery<AssigneePickerSearchAssignableRepositoryUsersQuery>(environment, SearchAssignableRepositoryUsers, {
          owner,
          name: repo,
          query,
          first: VALUES.maximumSuggestedUsers,
          capabilities,
        }).subscribe({
          next: (response: AssigneePickerSearchAssignableRepositoryUsersQuery$data) => {
            if (response !== null) {
              const assignableActors: Assignee[] = (response.repository?.suggestedActors?.nodes || []).flatMap(actor =>
                actor
                  ? // eslint-disable-next-line no-restricted-syntax
                    [readInlineData<AssigneePickerAssignee$key>(AssigneeFragment, actor)]
                  : [],
              )

              if (totalAssignableUsers === null)
                setTotalAssignableUsers(response.repository?.suggestedActors?.totalCount || 0)

              if (props.noAssigneeOption && hasFuzzyMatch(query, props.noAssigneeOption?.source?.login ?? '')) {
                assignableActors.unshift({
                  ...SPECIAL_VALUES.noAssigneeData,
                } as Assignee)
              }

              setIsLoading(false)
              resolve(assignableActors)
            }
          },
          error: (error: Error) => {
            reject(error)
            setIsLoading(false)
          },
        })
      })
    },
    [totalAssignableUsers, suggestedAssignees, props.noAssigneeOption, environment, owner, repo, capabilities],
  )

  const suggestedActors: Assignee[] = useMemo(() => {
    let all: Assignee[] = []
    if (assignees.length > 0) {
      all = assignees
    } else if (assigneeTokens.length > 0) {
      all = (data?.repository?.suggestedActors?.nodes || []).flatMap(actor =>
        actor
          ? // eslint-disable-next-line no-restricted-syntax
            [readInlineData<AssigneePickerAssignee$key>(AssigneeFragment, actor)]
          : [],
      )
    }

    if (props.noAssigneeOption?.selected) {
      all.unshift(SPECIAL_VALUES.noAssigneeData as Assignee)
    }

    return all
  }, [assigneeTokens.length, assignees, data?.repository?.suggestedActors?.nodes, props.noAssigneeOption?.selected])

  useEffect(() => {
    const fetchSuggestedAssignees = async () => {
      const result = await searchAssignees('')
      setSuggestedAssignees(result)
      setIsLoading(false)
    }

    fetchSuggestedAssignees()
    // disabling this as we only want to fetch the suggested assignees once
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const suggestedItems = useMemo(() => {
    const copilot = (suggestedAssignees || []).find(a => a.isCopilot)
    // create a new array instance because if we need to insert copilot
    // we need a new instance to force a re-render of the child component (ItemPickerWrapper)
    const source = [...(suggestions ? suggestions : suggestedAssignees || [])]

    if (copilot && !source.find(a => a.isCopilot)) {
      source.unshift(copilot)
    }

    return source
  }, [suggestedAssignees, suggestions])

  return (
    <ItemPickerWrapper
      {...props}
      assignees={suggestedActors}
      suggestions={suggestedItems}
      repo={repo}
      owner={owner}
      isLoading={isLoading}
      searchAssignees={searchAssignees}
      maximumAssignees={maximumAssignees}
    />
  )
}

function AssigneePickerInternal({
  number,
  owner,
  repo,
  assignees,
  suggestions,
  maximumAssignees,
  ...props
}: AssigneeIssuePickerProps) {
  const environment = useRelayEnvironment()
  const hasPreloadedData = (suggestions?.length || 0) > 0
  const [isLoading, setIsLoading] = useState(!hasPreloadedData)
  const [data, setData] = useState<AssigneePickerSearchAssignableUsersQuery$data | null>(null)

  useEffect(() => {
    if (!IS_SERVER && !hasPreloadedData) {
      clientSideRelayFetchQueryRetained<AssigneePickerSearchAssignableUsersQuery>({
        environment,
        query: SearchAssignableUsersQuery,
        variables: {owner, name: repo, number, query: '', first: 10},
      }).subscribe({
        next: internalData => {
          setData(internalData ?? null)
          setIsLoading(false)
        },
        error: () => {
          setIsLoading(false)
        },
      })
    }
  }, [environment, owner, repo, number, hasPreloadedData])

  const suggestedActors = suggestions
    ? suggestions
    : (data?.repository?.issueOrPullRequest?.suggestedActors?.nodes || []).flatMap(actor =>
        actor
          ? [
              // eslint-disable-next-line no-restricted-syntax
              readInlineData<AssigneePickerAssignee$key>(AssigneeFragment, actor),
            ]
          : [],
      )

  const searchAssignees = useCallback(
    (query: string) => {
      return new Promise<Assignee[]>((resolve, reject) => {
        fetchQuery<AssigneePickerSearchAssignableUsersQuery>(environment, SearchAssignableUsersQuery, {
          owner,
          name: repo,
          number,
          first: 10,
          query,
        }).subscribe({
          next: (response: AssigneePickerSearchAssignableUsersQuery$data) => {
            if (response !== null) {
              const assignableActorNodes = (
                response.repository?.issueOrPullRequest?.suggestedActors?.nodes || []
              ).flatMap(
                // eslint-disable-next-line no-restricted-syntax
                node => (node ? [readInlineData<AssigneePickerAssignee$key>(AssigneeFragment, node)] : []),
              )

              resolve(assignableActorNodes)
            }
          },
          error: (error: Error) => {
            reject(error)
          },
        })
      })
    },
    [environment, number, owner, repo],
  )

  return (
    <ItemPickerWrapper
      {...props}
      repo={repo}
      owner={owner}
      isLoading={isLoading}
      assignees={assignees}
      suggestions={suggestedActors}
      maximumAssignees={maximumAssignees}
      searchAssignees={searchAssignees}
    />
  )
}

function ItemPickerWrapper({
  assignees,
  suggestions,
  searchAssignees,
  onSelectionChange,
  insidePortal,
  anchorElement,
  nested,
  isLoading = false,
  noAssigneeOption = undefined,
  triggerOpen,
  selectionVariant = 'multiple',
  title,
  maximumAssignees,
  name = 'assignee',
  showNoMatchItem = false,
}: ItemPickerWrapperProps) {
  const [filter, setFilter] = useState('')
  const [searchResults, setSearchResults] = useState<Assignee[] | undefined>(undefined)
  const filterRef = useRef(filter)
  const viewer = useViewer()
  const {addToast} = useToastContext()

  const getItemKey = useCallback((assignee: Assignee) => assignee.login, [])

  const items = useMemo(() => {
    let sortedItems = []
    if (searchResults) {
      sortedItems = sortAssigneePickerUsers(assignees, searchResults, filter)
    } else {
      sortedItems = sortAssigneePickerUsers(
        assignees,
        assignees.concat(
          suggestions.filter(suggestion => !assignees.find(assignee => assignee.login === suggestion.login)),
        ),
        filter,
      )
    }

    if (viewer) {
      const currentUserIndex = sortedItems.findIndex(item => item.login === viewer.login)
      if (currentUserIndex !== -1) {
        // Remove the current user from its current position in the list to avoid duplicates
        sortedItems.splice(currentUserIndex, 1)
      } else if (searchResults) {
        // If the current user is not in the search results, we don't want to show it in the suggestions
        return sortedItems
      }
      // Add the current user to the top of the list
      sortedItems.unshift(viewer)
    }

    if (
      noAssigneeOption &&
      !noAssigneeOption.selected &&
      !sortedItems.find(i => i.id === SPECIAL_VALUES.noAssigneeData.id)
    ) {
      sortedItems.unshift(SPECIAL_VALUES.noAssigneeData as Assignee)
    }

    return sortedItems
  }, [searchResults, viewer, noAssigneeOption, assignees, filter, suggestions])

  const groupItemId = useCallback((assignee: Assignee) => getGroupItemId(assignees, assignee), [assignees])

  const convertToItemProps = useCallback(
    (assignee: Assignee): ExtendedItemProps<Assignee> => {
      if (noAssigneeOption && assignee.id === SPECIAL_VALUES.noAssigneeData.id) {
        const noAssigneeItem = {...noAssigneeOption}
        noAssigneeItem.groupId = groupItemId(assignee)
        return noAssigneeItem
      }
      if (showNoMatchItem && assignee.id === SPECIAL_VALUES.noMatchData.id) {
        return {
          ...SPECIAL_VALUES.noMatchData,
          groupId: groupItemId(assignee),
          source: assignee,
          text: `${name}:${filter}`,
          sx: {wordBreak: 'break-word'},
        }
      }
      const assigneeIsCopilot = assignee.isCopilot

      return {
        id: assignee.id,
        text: assigneeIsCopilot ? LABELS.copilotDisplayName : assignee.login,
        description: assigneeIsCopilot ? LABELS.copilotDescription : assignee.name ?? '',
        source: assignee,
        groupId: groupItemId(assignee),
        leadingVisual: () =>
          assigneeIsCopilot ? (
            isFeatureEnabled('use_copilot_avatar') ? (
              <CopilotAvatar />
            ) : (
              <CopilotIcon />
            )
          ) : assignee.avatarUrl.length === 0 ? null : (
            <GitHubAvatar alt={assignee.login} src={assignee.avatarUrl} />
          ),
        trailingVisual: () => (assignee.type === 'bot' ? <Label>bot</Label> : null),
        sx: {wordBreak: 'break-word'},
      }
    },
    [filter, groupItemId, name, noAssigneeOption, showNoMatchItem],
  )

  const onClose = useCallback(() => {
    setSearchResults(undefined)
  }, [])

  const fetchSearchData = useCallback(
    async (query: string) => {
      if (query === '') {
        setSearchResults(undefined)
        return
      }

      try {
        const suggestedAssignees = await searchAssignees(query)
        const currentFilter = filterRef.current
        if (query.trim() === currentFilter.trim()) {
          setSearchResults(suggestedAssignees)
        }
      } catch {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: ERRORS.couldNotSearchAssignees,
        })
      }
    },
    [addToast, searchAssignees],
  )

  const debounceFetchSearchData = useDebounce(
    (nextValue: string) => fetchSearchData(nextValue),
    VALUES.pickerDebounceTime,
    {
      leading: true,
      trailing: true,
      onChangeBehavior: 'flush',
    },
  )

  const filterItems = useCallback(
    (value: string) => {
      const trimmedFilter = value.trim()
      if (filter === trimmedFilter) return

      debounceFetchSearchData(trimmedFilter)
      setFilter(value)
      filterRef.current = trimmedFilter
    },
    [debounceFetchSearchData, filter],
  )

  const groups: ItemGroup[] = useMemo(() => {
    const itemGroups = []

    // Find items that are assignees and suggestions (non-assignees are suggestion items)
    const assigneeItems = items.filter(i => assignees.find(a => a.id === i.id))
    const suggestionItems = items.filter(i => !assignees.find(a => a.id === i.id))

    if (assigneeItems.length > 0) {
      itemGroups.push(assigneesGroup)
    }
    if (suggestionItems.length > 0) {
      itemGroups.push(suggestionsGroup)
    }
    return itemGroups
  }, [assignees, items])

  const anchorRef = useRef<HTMLButtonElement>(null)

  const showNoMatchMessage = useMemo(() => !showNoMatchItem && items.length === 0, [showNoMatchItem, items.length])
  return (
    <Box sx={{display: 'flex', flexDirection: 'row', flexWrap: 'wrap', gap: 1}}>
      <ItemPicker
        items={items}
        initialSelectedItems={assignees}
        loading={isLoading}
        filterItems={filterItems}
        title={title || LABELS.assigneesHeader(maximumAssignees ?? 10)}
        getItemKey={getItemKey}
        triggerOpen={triggerOpen}
        convertToItemProps={convertToItemProps}
        placeholderText={LABELS.filterUsers(name)}
        selectionVariant={maximumAssignees === 1 ? 'single' : selectionVariant || 'multiple'}
        onSelectionChange={onSelectionChange}
        onClose={onClose}
        renderAnchor={props => anchorElement(props, anchorRef)}
        groups={groups}
        insidePortal={insidePortal}
        height={'large'}
        width={'medium'}
        nested={nested}
        resultListAriaLabel={'User results'}
        selectPanelRef={anchorRef}
        subtitle={
          assignees.length === maximumAssignees ? (
            <Banner className={assigneePickerStyles.banner} variant="warning" hideTitle title="Assignee limit reached">
              {LABELS.limitWarning(maximumAssignees)}
            </Banner>
          ) : undefined
        }
        customNoMatchItem={
          showNoMatchItem
            ? ({
                id: SPECIAL_VALUES.noMatchData.id,
                avatarUrl: SPECIAL_VALUES.noMatchData.avatarUrl,
                login: filter,
              } as Omit<Assignee, '$fragmentType'>)
            : undefined
        }
        improvedNoMatchAccessibility={showNoMatchMessage}
        noMatchMessage={
          showNoMatchMessage
            ? {
                title: 'No assignees were found',
                body: 'Try searching for a different name for results.',
                variant: 'empty',
              }
            : undefined
        }
        keybindingCommandId={getKeyBindingCommandId(name)}
      />
    </Box>
  )
}

export function BulkIssuesAssigneePicker({
  useQueryForAction,
  repositoryId,
  query,
  issuesToActOn,
  assigneesAppliedToAll,
  assigneesAppliedToSome: _assigneesAppliedToSome,
  existingIssueAssignees,
  connectionIds,
  onError,
  onCompleted,
  ...rest
}: BulkAssigneePickerProps) {
  const environment = useRelayEnvironment()

  const onSelectionChange = useCallback(
    (selectedAssignees: Assignee[]) => {
      const assigneesToAdd = selectedAssignees.filter(a => !assigneesAppliedToAll.some(aa => aa.id === a.id))
      const assigneesToRemove = assigneesAppliedToAll.filter(a => !selectedAssignees.some(aa => aa.id === a.id))

      const args = {
        applyAssigneeIds: assigneesToAdd.map(l => l.id),
        removeAssigneeIds: assigneesToRemove.map(l => l.id),
      }

      const mutationArgs = {
        environment,
        optimisticUpdateIds: issuesToActOn,
        existingIssueAssignees,
        connectionIds,
        onError: (error: Error) => {
          onError?.(error)
        },
      }
      if (useQueryForAction && repositoryId && query) {
        commitUpdateIssueAssigneesBulkByQueryMutation({
          ...mutationArgs,
          input: {
            repositoryId,
            query,
            ...args,
          },
          onCompleted: ({updateIssuesBulkByQuery}: updateIssueAssigneesBulkByQueryMutation$data) => {
            onCompleted?.(updateIssuesBulkByQuery?.jobId || undefined)
          },
        })
      } else {
        commitUpdateIssueAssigneesBulkMutation({
          ...mutationArgs,
          input: {
            ids: [...issuesToActOn],
            ...args,
          },
          onCompleted: ({updateIssuesBulk}: updateIssueAssigneesBulkMutation$data) => {
            onCompleted?.(updateIssuesBulk?.jobId || undefined)
          },
        })
      }
    },
    [
      assigneesAppliedToAll,
      connectionIds,
      environment,
      existingIssueAssignees,
      issuesToActOn,
      onCompleted,
      onError,
      query,
      repositoryId,
      useQueryForAction,
    ],
  )

  return (
    <AssigneeRepositoryPicker
      {...rest}
      assignees={assigneesAppliedToAll}
      assigneeTokens={[]}
      onSelectionChange={onSelectionChange}
      includeAssignableBots
      includeAuthorableBots={false}
    />
  )
}

const getKeyBindingCommandId = (name?: string) =>
  name === 'author' ? 'item-pickers:open-author' : 'item-pickers:open-assignees'
