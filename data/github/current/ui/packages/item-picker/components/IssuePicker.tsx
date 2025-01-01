import type React from 'react'
import {useCallback, useEffect, useRef, useState, type Dispatch} from 'react'
import {graphql, useRelayEnvironment} from 'react-relay'

import {LABELS} from '../constants/labels'
import {ItemPicker} from './ItemPicker'
import type {ItemGroup} from '../shared'
import {useItemPickerErrorFallback} from '../hooks/useItemPickerErrorFallback'
import {clientSideRelayFetchQueryRetained} from '@github-ui/relay-environment'
import type {IssuePickerIssue$data} from './__generated__/IssuePickerIssue.graphql'
import {Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import type {
  IssuePickerSelectedIssuesQuery,
  IssuePickerSelectedIssuesQuery$data,
} from './__generated__/IssuePickerSelectedIssuesQuery.graphql'
import {useIssueFiltering} from '../hooks/useIssueFiltering'
import {getIssueIconAndFill} from '../utils/issue-icon'

const getItemKey = (issue: IssuePickerItem) => issue.id

export type IssuePickerItem = Omit<IssuePickerIssue$data, ' $fragmentType'>

type IssuePickerBaseProps = {
  anchorElement: (props: React.HTMLAttributes<HTMLElement>) => JSX.Element
  onIssueUpdate?: () => void
  onIssueSelection: (issues: IssuePickerItem[]) => void
  repositoryNameWithOwner?: string
  title?: string | React.ReactElement
  triggerOpen?: boolean
  onClose?: () => void
  selectedIssueIds?: string[]
  hiddenIssueIds?: string[]
  pickerId?: string
}

type IssuePickerProps = IssuePickerBaseProps & {
  owner?: string
}

type IssuePickerInternalProps = IssuePickerBaseProps & {
  items: Map<string, IssuePickerItem>
  isLoading: boolean
  filter: string
  setFilter: Dispatch<string>
}

const selectedGroup = {groupId: 'selected'}
const suggestionGroup = {groupId: 'suggestions', header: {title: 'Suggestions', variant: 'filled'}}
const groups: ItemGroup[] = [selectedGroup, suggestionGroup]

export const IssuePickerSelectedIssuesGraphQLQuery = graphql`
  query IssuePickerSelectedIssuesQuery($ids: [ID!]!) {
    nodes(ids: $ids) {
      ...IssuePickerIssue @relay(mask: false)
    }
  }
`

export const IssueFragment = graphql`
  fragment IssuePickerIssue on Issue {
    id
    title
    state
    stateReason(enableDuplicate: true)
    repository {
      id
      nameWithOwner
    }
    # Adding this to the main fragment, although it's not used to avoid introducing relay in Memex
    # eslint-disable-next-line relay/unused-fields
    databaseId
    number
    # Used for optimistic updates when closing an issue as duplicate
    # eslint-disable-next-line relay/unused-fields
    url
    __typename
  }
`

export function IssuePicker({
  onIssueSelection,
  selectedIssueIds,
  hiddenIssueIds,
  owner,
  repositoryNameWithOwner,
  pickerId,
  ...rest
}: IssuePickerProps) {
  const [filter, setFilter] = useState('')
  const {isLoading, isError, items} = useIssueFiltering(filter, owner, repositoryNameWithOwner, hiddenIssueIds)

  // Render a fallback if there is an error fetching the data from the filter
  const {createFallbackComponent} = useItemPickerErrorFallback({
    errorMessage: LABELS.cantEditItems('issues'),
    anchorElement: rest.anchorElement,
    open: true,
  })
  if (isError) {
    return createFallbackComponent(() => {})
  }

  return (
    <IssuePickerInternal
      items={items}
      isLoading={isLoading}
      {...rest}
      selectedIssueIds={selectedIssueIds}
      hiddenIssueIds={hiddenIssueIds}
      filter={filter}
      setFilter={setFilter}
      onIssueSelection={onIssueSelection}
      repositoryNameWithOwner={repositoryNameWithOwner}
      pickerId={pickerId}
    />
  )
}

function IssuePickerInternal({
  items,
  onIssueSelection,
  anchorElement,
  setFilter,
  isLoading,
  title,
  onClose,
  triggerOpen,
  selectedIssueIds,
  filter,
  pickerId,
}: IssuePickerInternalProps) {
  const environment = useRelayEnvironment()
  const [fetchedSelectedIssues, setFetchedSelectedIssues] = useState<Record<string, IssuePickerItem>>({})

  const fetchSelectedIssues = useCallback(
    (ids: string[]) => {
      return new Promise<IssuePickerSelectedIssuesQuery$data>((resolve, reject) => {
        clientSideRelayFetchQueryRetained<IssuePickerSelectedIssuesQuery>({
          environment,
          query: IssuePickerSelectedIssuesGraphQLQuery,
          variables: {ids},
        }).subscribe({
          next: (fetchedData: IssuePickerSelectedIssuesQuery$data) => {
            if (fetchedData !== null) {
              resolve(fetchedData)
            }
          },
          error: (error: Error) => {
            reject(error)
          },
        })
      })
    },
    [environment],
  )

  useEffect(() => {
    // Wait until the data is fetched before fetching any missing selected issues
    if (isLoading) return

    async function doFetch(missingIssueIds: string[]) {
      const {nodes = []} = await fetchSelectedIssues(missingIssueIds)
      for (const node of nodes) {
        if (!node || node.__typename !== 'Issue') continue
        setFetchedSelectedIssues(loadedSelectedIssuesMap => {
          return {...loadedSelectedIssuesMap, [node.id]: node}
        })
      }
    }

    // Check if the selected issues are already fetched and cache
    // them to avoid bugs when they're not returned in subsequent queries
    if (selectedIssueIds) {
      const missingIssueIds = []
      for (const selectedIssueId of selectedIssueIds) {
        const foundSelectedIssue = items.get(selectedIssueId)

        if (foundSelectedIssue) {
          setFetchedSelectedIssues(loadedSelectedIssuesMap => {
            return {...loadedSelectedIssuesMap, [selectedIssueId]: foundSelectedIssue}
          })
        } else if (!fetchedSelectedIssues?.[selectedIssueId]) {
          missingIssueIds.push(selectedIssueId)
        }
      }

      if (missingIssueIds.length > 0) {
        doFetch(missingIssueIds)
      }
    }
    // We only need to run this after the initial query, as we'll have
    // cached the selected issues for subsequent queries.
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isLoading, items])

  // Merge the fetched selected issues with the queried issues and ensure there are no duplicates
  for (const [id, issue] of Object.entries(fetchedSelectedIssues)) {
    items.set(id, issue)
  }

  const allIssues = Array.from(items.values())

  // If the search term is a number and there is an issue with that number, move it to the front.
  // If the issue is already in the 0th position, do nothing.
  const foundIssueNumberIndex = allIssues.findIndex(i => i.number === Number(filter))
  if (foundIssueNumberIndex > 0) {
    const [issue] = allIssues.splice(foundIssueNumberIndex, 1)

    if (issue) {
      allIssues.unshift(issue)
    }
  }

  const convertToItemProps = useCallback(
    (issue: IssuePickerItem) => {
      const {icon, fill} = getIssueIconAndFill(issue.state, issue.stateReason)
      const issueIsSelected = selectedIssueIds?.includes(issue.id)

      return {
        id: issue.id,
        text: issue.title,
        sx: {wordBreak: 'break-word'},
        source: issue,
        groupId: issueIsSelected ? selectedGroup.groupId : suggestionGroup.groupId,
        leadingVisual: () => <Octicon icon={icon} sx={{path: {fill}}} />,
        trailingVisual: () => <Text sx={{color: 'fg.muted'}}>{`#${issue.number}`}</Text>,
        // Show NWO when the issue is selected as it might reside in another repository than what is being queried.
        description: issueIsSelected ? issue.repository.nameWithOwner : undefined,
        descriptionVariant: 'block' as const,
      }
    },
    [selectedIssueIds],
  )

  const issuePickerRef = useRef<HTMLButtonElement>(null)

  return (
    <ItemPicker
      loading={isLoading}
      items={allIssues}
      initialSelectedItems={selectedIssueIds || []}
      filterItems={setFilter}
      title={title || LABELS.issueHeader}
      getItemKey={getItemKey}
      convertToItemProps={convertToItemProps}
      placeholderText="Search issues"
      selectionVariant="single"
      onSelectionChange={onIssueSelection}
      renderAnchor={anchorElement}
      height="large"
      width="medium"
      maxVisibleItems={-1}
      resultListAriaLabel="issue results"
      selectPanelRef={issuePickerRef}
      triggerOpen={triggerOpen}
      groups={groups}
      onClose={onClose}
      pickerId={pickerId}
    />
  )
}
