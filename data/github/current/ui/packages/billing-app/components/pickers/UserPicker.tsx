import {GitHubAvatar} from '@github-ui/github-avatar'
import {ItemPicker} from '@github-ui/item-picker/ItemPicker'
import {debounce} from '@github/mini-throttle'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {TriangleDownIcon} from '@primer/octicons-react'
import {Box, Button} from '@primer/react'
import {useCallback, useMemo, useState, useEffect} from 'react'
import type {PreloadedQuery} from 'react-relay'
import {fetchQuery, graphql, readInlineData, usePreloadedQuery, useRelayEnvironment} from 'react-relay'
import {Spacing} from '../../utils'
import pluralize from 'pluralize'

import {SelectedRows} from './SelectedRows'

import type {UserPickerQuery as UserPickerQueryType} from './__generated__/UserPickerQuery.graphql'
import type {
  UserPickerUserFragment$key,
  UserPickerUserFragment$data,
} from './__generated__/UserPickerUserFragment.graphql'
import type {UserPickerEnterpriseOwnersQuery as UserPickerEnterpriseOwnersQueryType} from './__generated__/UserPickerEnterpriseOwnersQuery.graphql'

const ARIA_MESSAGES = {
  SEARCHING: 'Searching...',
  SEARCH_CLEARED: 'Search cleared',
  ERROR_SEARCHING: 'Search error',
  NO_USERS_FOUND: (query: string) => `No users found for "${query}"`,
  USERS_FOUND: (count: number, query: string) => `${count} ${pluralize('user', count)} found for "${query}"`,
  USERS_SELECTED: (count: number) => `${count} selected`,
} as const

export const UserPickerQuery = graphql`
  query UserPickerQuery($slug: String!, $query: String) {
    enterprise(slug: $slug) {
      members(first: 10, query: $query) {
        nodes {
          ... on EnterpriseUserAccount {
            user {
              ...UserPickerUserFragment
            }
          }
        }
      }
    }
  }
`

export const UserPickerUserFragment = graphql`
  fragment UserPickerUserFragment on User @inline {
    id
    login
    name
    avatarUrl(size: 64)
  }
`

export const UserPickerEnterpriseOwnersQuery = graphql`
  query UserPickerEnterpriseOwnersQuery($slug: String!) {
    enterprise(slug: $slug) {
      ownerInfo {
        admins(first: 10) {
          nodes {
            ...UserPickerUserFragment
          }
        }
      }
    }
  }
`

export const UserPickerInitialUsersQuery = graphql`
  query UserPickerInitialUsersQuery($ids: [ID!]!) {
    nodes(ids: $ids) {
      ...UserPickerUserFragment @dangerously_unaliased_fixme
    }
  }
`

interface Props {
  slug: string
  onSelectionChange: (selected: User[]) => void
  initialRecipients: User[]
  preloadedEnterpriseOwnersData: PreloadedQuery<UserPickerEnterpriseOwnersQueryType>
}

export type User = UserPickerUserFragment$data

const recipientsGroup = {groupId: 'recipients'}
const suggestionsGroup = {groupId: 'suggestions', header: {title: 'Suggestions', variant: 'filled'}}

const sortUsers = (recipients: User[], usersToSort: User[]) => {
  return usersToSort.slice().sort((a, b) => {
    const aIsRecipient = recipients.some(r => r.login === a.login)
    const bIsRecipient = recipients.some(r => r.login === b.login)
    if (aIsRecipient && !bIsRecipient) return -1
    if (bIsRecipient && !aIsRecipient) return 1
    return a.login.localeCompare(b.login)
  })
}

export const UserPicker = ({slug, onSelectionChange, preloadedEnterpriseOwnersData, initialRecipients}: Props) => {
  const [loading, setLoading] = useState<boolean>(false)
  const [searchResults, setSearchResults] = useState<User[] | undefined>()
  const [recipients, setRecipients] = useState<User[]>([])
  const [filter, setFilter] = useState<string>('')
  const [ariaMessage, setAriaMessage] = useState<string>('')
  const [shouldAnnounceResults, setShouldAnnounceResults] = useState<boolean>(false)
  const environment = useRelayEnvironment()
  const {addToast} = useToastContext()

  const enterpriseOwnersData = usePreloadedQuery<UserPickerEnterpriseOwnersQueryType>(
    UserPickerEnterpriseOwnersQuery,
    preloadedEnterpriseOwnersData,
  )
  const enterpriseOwners = (enterpriseOwnersData.enterprise?.ownerInfo?.admins.nodes || []).flatMap(node =>
    // eslint-disable-next-line no-restricted-syntax
    node ? [readInlineData<UserPickerUserFragment$key>(UserPickerUserFragment, node)] : [],
  )

  const getItemKey = useCallback((user: User) => user.login, [])

  const items = useMemo(() => {
    if (searchResults) {
      return sortUsers(recipients, searchResults)
    }
    if (enterpriseOwners.length > 0) {
      return sortUsers(
        recipients,
        recipients.concat(enterpriseOwners.filter(u => !recipients.find(r => r.login === u.login))),
      )
    }
    return recipients
  }, [searchResults, recipients, enterpriseOwners])

  useEffect(() => {
    setRecipients(initialRecipients)
  }, [initialRecipients])

  const groupItemId = useCallback(
    (user: User) => {
      if (recipients.find(r => r.id === user.id)) {
        return recipientsGroup.groupId
      }
      return suggestionsGroup.groupId
    },
    [recipients],
  )

  const convertToItemProps = useCallback(
    (user: User) => {
      return {
        id: user.id,
        text: user.login,
        description: user.name ?? '',
        source: user,
        groupId: groupItemId(user),
        leadingVisual: () => <GitHubAvatar src={user.avatarUrl} alt="" />,
        rowLeadingVisual: () => <GitHubAvatar src={user.avatarUrl} alt="" />,
        viewOnly: false,
      }
    },
    [groupItemId],
  )

  const onClose = useCallback(() => {
    setSearchResults(undefined)
  }, [])

  const removeOption = (id: string) => {
    const newRecipients = recipients.filter(r => r.id !== id)
    setRecipients(newRecipients)
    onSelectionChange(newRecipients)
  }

  const fetchSearchData = useCallback(
    (query: string) => {
      if (query === '') {
        setSearchResults(undefined)
        setShouldAnnounceResults(true)
        setAriaMessage(ARIA_MESSAGES.SEARCH_CLEARED)
        return
      }
      setLoading(true)
      fetchQuery<UserPickerQueryType>(environment, UserPickerQuery, {slug, query}).subscribe({
        next: data => {
          const nodes = (data.enterprise?.members.nodes || []).flatMap(node =>
            // eslint-disable-next-line no-restricted-syntax
            node?.user ? [readInlineData<UserPickerUserFragment$key>(UserPickerUserFragment, node.user)] : [],
          )
          setSearchResults(nodes)
          setLoading(false)
          setShouldAnnounceResults(true)

          if (nodes.length === 0) {
            setAriaMessage(ARIA_MESSAGES.NO_USERS_FOUND(query))
          } else {
            // Only announce detailed results for small result sets to reduce noise
            if (nodes.length <= 3) {
              setAriaMessage(ARIA_MESSAGES.USERS_FOUND(nodes.length, query))
            } else {
              setAriaMessage(`${nodes.length} users found`)
            }
          }
        },
        error: () => {
          setLoading(false)
          setShouldAnnounceResults(true)
          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            type: 'error',
            message: 'Unable to query users',
            role: 'alert',
          })
          setAriaMessage(ARIA_MESSAGES.ERROR_SEARCHING)
        },
      })
    },
    [slug, environment, addToast],
  )

  // eslint-disable-next-line react-hooks/react-compiler
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const debounceFetchSearchData = useCallback(
    debounce((nextValue: string) => fetchSearchData(nextValue), 200),
    [fetchSearchData],
  )

  const filterItems = useCallback(
    (value: string) => {
      const trimmedFilter = value.trim()
      if (filter !== trimmedFilter) {
        setAriaMessage(ARIA_MESSAGES.SEARCHING)
        setShouldAnnounceResults(false)
        debounceFetchSearchData(trimmedFilter)
      }
      setFilter(value)
    },
    [debounceFetchSearchData, filter],
  )

  const groups = useMemo(() => {
    const itemGroups = []

    const hasRecipients = items.some(i => recipients.find(r => r.id === i.id))
    const hasSuggestions = items.some(i => !recipients.find(r => r.id === i.id))

    if (hasRecipients) itemGroups.push(recipientsGroup)
    if (hasSuggestions) itemGroups.push(suggestionsGroup)
    return itemGroups
  }, [recipients, items])

  const onSelectedChanged = (selected: User[]) => {
    setRecipients(selected)
    onSelectionChange(selected)
    setShouldAnnounceResults(true)
    setAriaMessage(ARIA_MESSAGES.USERS_SELECTED(selected.length))
  }

  return (
    <div data-testid="user-picker">
      <Box sx={{mt: 2, mb: Spacing.StandardPadding}}>
        <ItemPicker
          items={items}
          initialSelectedItems={recipients}
          filterItems={filterItems}
          getItemKey={getItemKey}
          convertToItemProps={convertToItemProps}
          placeholderText="Search for users"
          selectionVariant="multiple"
          loading={loading}
          onSelectionChange={onSelectedChanged}
          onClose={onClose}
          renderAnchor={anchorProps => (
            <Button trailingAction={TriangleDownIcon} {...anchorProps}>
              Select recipients
            </Button>
          )}
          groups={groups}
          aria-label="User picker"
          // Enable improved accessibility to prevent "No matches" from being counted as selectable
          improvedNoMatchAccessibility
        />
      </Box>
      <div className="sr-only" role="status" aria-live="polite" aria-atomic="true">
        {shouldAnnounceResults ? ariaMessage : ''}
      </div>
      <SelectedRows removeOption={removeOption} selected={recipients.map(convertToItemProps)} />
    </div>
  )
}
