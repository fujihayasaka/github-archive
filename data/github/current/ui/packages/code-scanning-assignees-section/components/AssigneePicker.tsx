import {useCallback, useEffect, useMemo, useRef, useState, type RefObject} from 'react'
import type {Assignee, CodeScanningAssigneesRepository} from '../types'
import {VALUES} from '@github-ui/item-picker/Values'
import {useDebounce} from '@github-ui/use-debounce'
import {keepPreviousData} from '@github-ui/react-query'
import {useAvailableAssigneesQuery} from '../hooks/use-available-assignees-query'
import {ItemPicker, type ExtendedItemProps} from '@github-ui/item-picker/ItemPicker'
import {LABELS} from '@github-ui/item-picker/Labels'
import {CopilotIcon} from '@primer/octicons-react'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {Label} from '@primer/react'
import type {ItemGroup} from '@github-ui/item-picker/shared'
import {Banner} from '@primer/react/experimental'

type AssigneePickerSharedProps = {
  onSelectionChange: (selected: Assignee[]) => void
  shortcutsEnabled: boolean
  anchorElement: (props: React.HTMLAttributes<HTMLElement>, ref: RefObject<HTMLButtonElement>) => JSX.Element
  subtitle?: string | React.ReactElement
  title?: string | React.ReactElement
  currentUser: Assignee | null
  maximumAssignees: number
  triggerOpen?: boolean
  onOpen?: () => void
  onClose?: () => void
  preventClose?: boolean
  loading?: boolean
}

export type AssigneePickerProps = AssigneePickerSharedProps & {
  repository: CodeScanningAssigneesRepository
  initialSelectedAssignees: Assignee[]
  preventClose?: boolean
  mutationError: Error | null
}

type AssigneePickerInternalProps = AssigneePickerSharedProps & {
  initialSelectedAssignees: Assignee[]
  foundAssignees: Assignee[]
  onFilter: (value: string) => void
  searchError: Error | null
  mutationError: Error | null
  filter: string
}

export type AssigneePickerBaseProps = Omit<AssigneePickerInternalProps, 'foundAssignees'> & {
  assigneeItems: Assignee[]
  currentUser: Assignee | null
}

export const assigneesGroup: ItemGroup = {groupId: 'assignees'}
export const suggestionsGroup: ItemGroup = {groupId: 'suggestions', header: {title: 'Suggestions', variant: 'filled'}}
const getItemKey = (assignee: Assignee) => assignee.login

export const AssigneePicker = ({repository, initialSelectedAssignees, loading, ...rest}: AssigneePickerProps) => {
  const [isOpened, setIsOpened] = useState(false)
  const [filter, setFilter] = useState('')
  const [debouncedFilter, setDebouncedFilter] = useState('')

  const updateDebouncedFilter = useDebounce((newFilter: string) => {
    setDebouncedFilter(newFilter)
  }, VALUES.pickerDebounceTime)

  useEffect(() => {
    updateDebouncedFilter(filter)
  }, [updateDebouncedFilter, filter])

  const {data, isPending, isRefetching, error} = useAvailableAssigneesQuery(
    {
      owner: repository.ownerLogin,
      repo: repository.name,
      query: debouncedFilter,
    },
    {
      // This makes the functional be like an autocomplete widget.
      // For example, you type "a" and it suggests "Anders, Ant, Apple".
      // then, when you type "an", until new results are fetched, it continues to
      // show "Anders, Ant, Apple" (the previous results), even though "Apple" should
      // cease to be suggested.
      // But the alternative to using this technique is causing flicker. After you've keypressed
      // "an", it would remove all suggestions and only show suggestions when it has "Anders, Ant"
      // left to show.
      placeholderData: keepPreviousData,
      // Simply opening the menu means we're going to trigger a "search"
      // even though the user might not have typed in any search string.
      enabled: isOpened,
    },
  )

  return (
    <AssigneePickerInternal
      initialSelectedAssignees={initialSelectedAssignees}
      foundAssignees={data?.users ?? []}
      onOpen={() => setIsOpened(true)}
      onClose={() => setIsOpened(false)}
      onFilter={setFilter}
      filter={debouncedFilter}
      // The first `loading` is coming from outside the component.
      // The `isPending` is for the first search XHR.
      // The `isRefetching` is for any following search XHR. This is how it
      // work when you use `placeholderData: keepPreviousData` in useQuery.
      loading={loading || isPending || isRefetching}
      searchError={error}
      {...rest}
    />
  )
}

function AssigneePickerInternal({initialSelectedAssignees, foundAssignees, ...rest}: AssigneePickerInternalProps) {
  const assigneeItems = initialSelectedAssignees.concat(
    foundAssignees.filter(item => !initialSelectedAssignees.some(a => a.id === item.id)),
  )

  return (
    <AssigneePickerBase initialSelectedAssignees={initialSelectedAssignees} assigneeItems={assigneeItems} {...rest} />
  )
}

export function AssigneePickerBase({
  assigneeItems,
  initialSelectedAssignees,
  currentUser,
  maximumAssignees,
  filter,
  loading,
  onFilter,
  anchorElement,
  shortcutsEnabled,
  searchError,
  mutationError,
  ...rest
}: AssigneePickerBaseProps) {
  const items = useMemo(() => {
    const sortedItems = sortAssigneePickerUsers(initialSelectedAssignees, assigneeItems, filter)

    if (currentUser) {
      const currentUserIndex = sortedItems.findIndex(item => item.id === currentUser.id)
      if (currentUserIndex !== -1) {
        // Remove the current user from its current position in the list to avoid duplicates
        sortedItems.splice(currentUserIndex, 1)
      } else if (filter !== '') {
        // If the current user is not in the search results, we don't want to show it in the suggestions
        return sortedItems
      }
      // Add the current user to the top of the list
      sortedItems.unshift(currentUser)
    }

    return sortedItems
  }, [initialSelectedAssignees, assigneeItems, filter, currentUser])

  const convertToItemProps = useCallback(
    (assignee: Assignee): ExtendedItemProps<Assignee> => {
      return {
        id: assignee.id,
        text: assignee.isCopilot ? LABELS.copilotDisplayName : assignee.login,
        description: assignee.isCopilot ? LABELS.copilotDescription : assignee.name ?? '',
        source: assignee,
        groupId: initialSelectedAssignees.find(a => a.id === assignee.id)
          ? assigneesGroup.groupId
          : suggestionsGroup.groupId,
        leadingVisual: () =>
          assignee.isCopilot ? (
            <CopilotIcon />
          ) : assignee.avatarUrl.length === 0 ? null : (
            <GitHubAvatar alt={`@${assignee.login}`} src={assignee.avatarUrl} />
          ),
        trailingVisual: () => (assignee.isCopilot ? <Label>bot</Label> : null),
        sx: {wordBreak: 'break-word'},
      }
    },
    [initialSelectedAssignees],
  )

  const groups: ItemGroup[] = useMemo(() => {
    const itemGroups = []

    // Find items that are assignees and suggestions (non-assignees are suggestion items)
    const selectedItems = assigneeItems.filter(i => initialSelectedAssignees.find(a => a.id === i.id))
    const suggestionItems = assigneeItems.filter(i => !initialSelectedAssignees.find(a => a.id === i.id))

    if (selectedItems.length > 0) {
      itemGroups.push(assigneesGroup)
    }
    if (suggestionItems.length > 0) {
      itemGroups.push(suggestionsGroup)
    }
    return itemGroups
  }, [assigneeItems, initialSelectedAssignees])

  const anchorRef = useRef<HTMLButtonElement>(null)

  const subtitle = useMemo(() => {
    if (searchError) {
      return (
        <Banner
          aria-label="Critical"
          title="Search error"
          description="Unable to complete the search for assignees. Try again later."
          variant="critical"
        />
      )
    }

    if (mutationError) {
      return (
        <Banner
          aria-label="Critical"
          title="Save error"
          description="Unable to save your selection due to server error. Try again later."
          variant="critical"
        />
      )
    }

    if (initialSelectedAssignees.length >= maximumAssignees) {
      return (
        <Banner
          aria-label="Warning"
          title="Assignee limit reached"
          description={`You have reached the limit of ${maximumAssignees} assignees`}
          variant="warning"
        />
      )
    }

    return undefined
  }, [searchError, mutationError, initialSelectedAssignees.length, maximumAssignees])

  return (
    <div className="d-flex flex-row flex-wrap gap-4">
      <ItemPicker<Assignee>
        loading={loading}
        items={items}
        initialSelectedItems={initialSelectedAssignees}
        groups={groups}
        filterItems={onFilter}
        getItemKey={getItemKey}
        convertToItemProps={convertToItemProps}
        placeholderText="Filter assignees"
        selectionVariant="multiple"
        selectPanelRef={anchorRef}
        renderAnchor={props => anchorElement(props, anchorRef)}
        width="medium"
        resultListAriaLabel="Assignee search results"
        height="large"
        subtitle={subtitle}
        {...rest}
      />
    </div>
  )
}

function assigneeMatchesQuery(user: Assignee, query: string) {
  return `${user.login.toLowerCase()}#${user.name?.toLowerCase()}`.includes(query)
}

export function sortAssigneePickerUsers(assignees: Assignee[], usersToSort: Assignee[], query: string) {
  const lowercasedQuery = query.toLowerCase().trim()
  // If any of the assignees matches the filter, put them on top
  const filteredAssignees = assignees.filter(u => assigneeMatchesQuery(u, lowercasedQuery))
  // Remove all the assignees from the possible result set
  const filteredUsersToSort = usersToSort.filter(
    userToSort => !filteredAssignees.some(assignee => assignee.id === userToSort.id),
  )
  filteredUsersToSort.sort((a, b) => {
    // Sort Copilot users to the top
    if (a.isCopilot !== b.isCopilot) {
      return a.isCopilot ? -1 : 1
    }

    // Then sort alphabetically by login
    return a.login.localeCompare(b.login)
  })

  return filteredAssignees.concat(filteredUsersToSort)
}
