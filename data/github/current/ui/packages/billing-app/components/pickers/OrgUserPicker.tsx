import {GitHubAvatar} from '@github-ui/github-avatar'
import {ItemPicker} from '@github-ui/item-picker/ItemPicker'
import {debounce} from '@github/mini-throttle'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {TriangleDownIcon} from '@primer/octicons-react'
import {Box, Button} from '@primer/react'
import {useCallback, useMemo, useState, useEffect} from 'react'
import {fetchQuery, graphql, readInlineData, useRelayEnvironment} from 'react-relay'

import {Spacing} from '../../utils'

import {SelectedRows} from './SelectedRows'

import {UserPickerUserFragment} from './UserPicker'

import type {OrgUserPickerQuery as OrgUserPickerQueryType} from './__generated__/OrgUserPickerQuery.graphql'
import type {
  UserPickerUserFragment$key,
  UserPickerUserFragment$data,
} from './__generated__/UserPickerUserFragment.graphql'

export const OrgUserPickerQuery = graphql`
  query OrgUserPickerQuery($orgName: String!) {
    organization(login: $orgName) {
      membersWithRole(first: 10) {
        nodes {
          ... on User {
            ...UserPickerUserFragment
          }
        }
      }
    }
  }
`

interface Props {
  orgName: string
  onSelectionChange: (selected: User[]) => void
  initialRecipients: User[]
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

export const OrgUserPicker = ({orgName, onSelectionChange, initialRecipients}: Props) => {
  const [loading, setLoading] = useState<boolean>(false)
  const [searchResults, setSearchResults] = useState<User[] | undefined>()
  const [initialUsers, setInitialUsers] = useState<User[] | undefined>()
  const [recipients, setRecipients] = useState<User[]>([])
  const [filter, setFilter] = useState<string>('')
  const environment = useRelayEnvironment()
  const {addToast} = useToastContext()

  const getItemKey = useCallback((user: User) => user.login, [])

  const items = useMemo(() => {
    if (searchResults) {
      return sortUsers(recipients, searchResults)
    }
    return sortUsers(recipients, initialUsers ?? [])
  }, [searchResults, recipients, initialUsers])

  useEffect(() => {
    setRecipients(initialRecipients)
  }, [initialRecipients])

  useEffect(() => {
    // Fetch initial data when the component mounts
    fetchSearchData('')
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

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
        leadingVisual: () => <GitHubAvatar src={user.avatarUrl} alt={user.name ?? ''} />,
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
      setLoading(true)
      fetchQuery<OrgUserPickerQueryType>(environment, OrgUserPickerQuery, {orgName}).subscribe({
        next: data => {
          const nodes = (data.organization?.membersWithRole.nodes || []).flatMap(node =>
            // eslint-disable-next-line no-restricted-syntax
            node ? [readInlineData<UserPickerUserFragment$key>(UserPickerUserFragment, node)] : [],
          )
          // filter nodes based off query search
          if (query === '') {
            setSearchResults(undefined)
            setInitialUsers(nodes)
          } else {
            const queryLower = query.toLowerCase()
            const filtered_nodes = nodes.filter(
              node =>
                node.login.toLowerCase().includes(queryLower) ||
                (node.name && node.name.toLowerCase().includes(queryLower)),
            )
            setSearchResults(filtered_nodes)
          }
          setLoading(false)
        },
        error: (err: unknown) => {
          setLoading(false)
          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            type: 'error',
            message: `Unable to query users: ${err}`,
            role: 'alert',
          })
        },
      })
    },
    [environment, orgName, addToast],
  )

  // eslint-disable-next-line react-compiler/react-compiler
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const debounceFetchSearchData = useCallback(
    debounce((nextValue: string) => fetchSearchData(nextValue), 200),
    [fetchSearchData],
  )

  const filterItems = useCallback(
    (value: string) => {
      const trimmedFilter = value.trim()
      if (filter !== trimmedFilter) {
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
        />
      </Box>
      <SelectedRows removeOption={removeOption} selected={recipients.map(convertToItemProps)} />
    </div>
  )
}
