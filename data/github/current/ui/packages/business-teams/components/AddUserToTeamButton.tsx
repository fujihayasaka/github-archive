import {useState} from 'react'
import {Banner, SelectPanel} from '@primer/react/experimental'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, Box, Button, Checkbox, CheckboxGroup, FormControl, Text, Spinner} from '@primer/react'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useMutation, useQuery} from '@github-ui/react-query'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {useDebounce} from '@github-ui/use-debounce'

export interface AddUserToTeamButtonProps {
  inactive: boolean
  enterpriseSlug: string
  teamSlug: string
  membersAllowedToAdd: number
  teamMembersLimit: number
  addMembersToTable: (newUser: User[]) => void
}

interface User {
  displayLogin: string
  id: number
  profileName: string
  avatarUrl: string
}

interface EligibleUsersData {
  totalEligibleUsersInEnterprise: number
  users: User[]
}

const AddUserToTeamButton: React.FC<AddUserToTeamButtonProps> = payload => {
  const {addMembersToTable, inactive, membersAllowedToAdd, teamMembersLimit} = payload
  const [selectedUsers, setSelectedUsers] = useState<User[]>([])
  const [filter, setFilter] = useState('')
  const [debouncedFilter, setDebouncedFilter] = useState('')
  const [dropdownOpen, setDropdownOpen] = useState(false)
  const [addAllEnterpriseMembersSelected, setAddAllEnterpriseMembersSelected] = useState(false)
  const pageSize = 30
  const allowedToAddSelectedUsers = membersAllowedToAdd > 0 && selectedUsers.length <= membersAllowedToAdd

  const {
    isError: searchQueryError,
    isPending: searchQueryPending,
    data: searchResults,
  } = useQuery<EligibleUsersData>({
    queryKey: ['nonMembers', payload.enterpriseSlug, payload.teamSlug, debouncedFilter],
    queryFn: async () => {
      const params = new URLSearchParams({
        query: debouncedFilter,
        page_size: pageSize.toString(),
      })
      const response = await verifiedFetchJSON(
        `/enterprises/${payload.enterpriseSlug}/teams/${payload.teamSlug}/eligible_members?${params}`,
      )

      if (response.ok) {
        return await response.json()
      } else {
        throw new Error(`${response.status} on ${response.url}`)
      }
    },
    enabled: dropdownOpen,
  })
  const totalEligibleUsersInEnterprise: number = searchResults?.totalEligibleUsersInEnterprise || -1
  const nonMembers: User[] = searchResults?.users || []

  const {
    mutate: saveMutation,
    isError: saveMutationError,
    isPending: saveMutationPending,
  } = useMutation({
    mutationFn: async () => {
      const response = await verifiedFetchJSON(
        `/enterprises/${payload.enterpriseSlug}/teams/${payload.teamSlug}/members`,
        {
          method: 'POST',
          body: {
            select_all_in_enterprise: addAllEnterpriseMembersSelected,
            user_ids: addAllEnterpriseMembersSelected ? [] : selectedUsers.map(item => item.id),
          },
        },
      )

      if (response.ok) {
        return response.json()
      }
      throw new Error(`${response.status} on ${response.url}`)
    },
    onSuccess: async () => {
      addMembersToTable(selectedUsers)
      closeDropdown()
      await getQueryClient().invalidateQueries({queryKey: ['nonMembers', payload.enterpriseSlug, payload.teamSlug]})
    },
  })

  const allUsersSelected = (): boolean => {
    return selectedUsers.length === nonMembers.length
  }

  function handleFilterChange(newFilter: string) {
    setFilter(newFilter)
    updateDebouncedFilter(newFilter)
  }

  const updateDebouncedFilter = useDebounce((newFilter: string) => {
    setDebouncedFilter(newFilter)
  }, 300)

  function handleSelectAllClicked() {
    if (allUsersSelected()) {
      setSelectedUsers([])
      setAddAllEnterpriseMembersSelected(false)
    } else {
      setSelectedUsers(nonMembers)
    }
  }

  function closeDropdown() {
    setDropdownOpen(false)
    setSelectedUsers([])
    setFilter('')
    setDebouncedFilter('')
    setAddAllEnterpriseMembersSelected(false)
  }

  function showDropdown() {
    setDropdownOpen(true)
  }

  function handleUserSelected(user: User) {
    const selectedUserIndex = selectedUsers.findIndex(selectedItem => selectedItem.id === user.id)
    if (selectedUserIndex === -1) {
      setSelectedUsers(previouslySelected => {
        return [...previouslySelected, user]
      })
    } else {
      setSelectedUsers(previouslySelected => {
        return previouslySelected.filter(u => u.id !== user.id)
      })
    }
  }

  return (
    <SelectPanel
      title="Select members"
      selectionVariant="multiple"
      onCancel={closeDropdown}
      onSubmit={() => saveMutation()}
      open={dropdownOpen}
    >
      <SelectPanel.Button
        data-testid="add-members-button"
        inactive={inactive}
        trailingAction={TriangleDownIcon}
        variant={inactive ? 'default' : 'primary'}
        onClick={showDropdown}
      >
        Add members
      </SelectPanel.Button>

      <SelectPanel.Header>
        {(searchQueryError || saveMutationError) && (
          <Banner
            hideTitle
            title="Failed to add members"
            data-testid="flash-error"
            variant="critical"
            style={{marginTop: 8}}
          >
            Something went wrong. Please try again.
          </Banner>
        )}
        {!allowedToAddSelectedUsers && (
          <Banner
            hideTitle
            title={`Team member limit (${teamMembersLimit}) reached.`}
            data-testid="team-members-limit-error"
            variant="warning"
            style={{marginTop: 8}}
          >
            The team member limit is {teamMembersLimit}. Adjust your selection to add a new member.
          </Banner>
        )}
        <SelectPanel.SearchInput
          data-testid="search-members-input"
          onChange={e => handleFilterChange(e.target.value)}
          placeholder="Search members"
          aria-label="Search for a member"
        />
      </SelectPanel.Header>

      {saveMutationPending || searchQueryPending || filter !== debouncedFilter ? (
        <SelectPanel.Message variant="empty" title="">
          <Spinner />
        </SelectPanel.Message>
      ) : nonMembers.length === 0 ? (
        debouncedFilter === '' ? (
          <SelectPanel.Message variant="empty" title="No more enterprise members to add">
            <span data-testid="no-users-remaining-text">
              All members of your enterprise have been added to this team.
            </span>
          </SelectPanel.Message>
        ) : (
          <SelectPanel.Message variant="empty" title="No enterprise members found">
            <span data-testid="no-users-found-text">Try a different search term</span>
          </SelectPanel.Message>
        )
      ) : (
        <ActionList selectionVariant="multiple" sx={{pt: 0}}>
          {filter === '' && debouncedFilter === '' && (
            <Box
              sx={{
                bg: 'canvas.subtle',
                borderBottom: '1px solid',
                borderBottomColor: 'border.muted',
              }}
            >
              <CheckboxGroup sx={{py: 2, px: 3}} aria-labelledby="select-all">
                <Box sx={{display: 'flex'}}>
                  <FormControl sx={{alignItems: 'center'}}>
                    <Checkbox
                      aria-labelledby="select-all"
                      checked={allUsersSelected()}
                      onChange={handleSelectAllClicked}
                      indeterminate={!allUsersSelected() && selectedUsers.length > 0}
                      data-testid="select-all-checkbox"
                    />
                    <FormControl.Label aria-labelledby="select-all" id="select-all" sx={{color: 'fg.muted'}}>
                      <span>Select all</span>
                    </FormControl.Label>
                  </FormControl>
                </Box>
              </CheckboxGroup>
            </Box>
          )}
          <Box sx={{marginBottom: 2}}>
            {debouncedFilter === '' &&
              selectedUsers.length === pageSize &&
              pageSize < totalEligibleUsersInEnterprise && (
                <Box
                  sx={{
                    borderBottom: '1px solid',
                    borderBottomColor: 'border.muted',
                  }}
                >
                  <CheckboxGroup sx={{py: 2, px: 3}} aria-labelledby="select-all">
                    <Box sx={{display: 'flex'}}>
                      <FormControl sx={{alignItems: 'center'}}>
                        <FormControl.Caption aria-labelledby="select-all" id="select-all" sx={{color: 'fg.muted'}}>
                          <span>
                            {addAllEnterpriseMembersSelected ? (
                              <span>
                                <b>All {totalEligibleUsersInEnterprise} users</b> are selected.
                              </span>
                            ) : (
                              <span>
                                <b>{selectedUsers.length} users</b> are selected.
                              </span>
                            )}{' '}
                            <Button
                              onClick={() => setAddAllEnterpriseMembersSelected(!addAllEnterpriseMembersSelected)}
                              variant="link"
                            >
                              <u>
                                {addAllEnterpriseMembersSelected
                                  ? 'Clear selection'
                                  : `Select all ${totalEligibleUsersInEnterprise}`}
                              </u>
                            </Button>
                          </span>
                        </FormControl.Caption>
                      </FormControl>
                    </Box>
                  </CheckboxGroup>
                </Box>
              )}
          </Box>

          {addAllEnterpriseMembersSelected ? (
            <SelectPanel.Message variant="empty" title="All enterprise members selected">
              <span style={{marginBottom: '25%'}}>
                You&apos;ve selected all {totalEligibleUsersInEnterprise} eligible members
              </span>
            </SelectPanel.Message>
          ) : (
            nonMembers.map((user, index) => (
              <ActionList.Item
                key={user.id}
                onSelect={() => handleUserSelected(user)}
                selected={selectedUsers.some(selectedUser => selectedUser.id === user.id)}
                aria-labelledby={`enterprise-member-${index}`}
                data-testid={`enterprise-member-${index}`}
              >
                <Box sx={{display: 'flex', alignItems: 'flex-start', gap: '8px'}}>
                  <Box sx={{display: 'flex', flexDirection: 'column', justifyContent: 'center'}} style={{borderTop: 1}}>
                    <GitHubAvatar sx={{ml: '1px', mt: '2px'}} size={16} src={user.avatarUrl} alt="User avatar" />
                  </Box>
                  <Box
                    id={`enterprise-member-${index}`}
                    sx={{display: 'flex', fontSize: '14px', alignItems: 'baseline', flexGrow: 1}}
                  >
                    <div>
                      <Text sx={{fontWeight: 'bold'}}>{user.displayLogin}</Text>
                      &nbsp;
                      <Text sx={{color: 'var(--fgColor-muted)'}}>{user.profileName}</Text>
                    </div>
                  </Box>
                </Box>
              </ActionList.Item>
            ))
          )}
        </ActionList>
      )}
      {!allowedToAddSelectedUsers ? (
        <Box
          sx={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            flexShrink: 0,
            minHeight: '44px',
            padding: 3,
            borderTop: '1px solid',
            borderColor: 'border.default',
          }}
        >
          <div />
          <Box sx={{display: 'flex', gap: 2}}>
            <Button type="button" onClick={closeDropdown} size="small">
              Cancel
            </Button>
            <Button inactive type="submit" variant="primary" size="small">
              Save
            </Button>
          </Box>
        </Box>
      ) : (
        <SelectPanel.Footer />
      )}
    </SelectPanel>
  )
}

export default AddUserToTeamButton
