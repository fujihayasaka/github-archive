import {Button, Dialog} from '@primer/react'
import {ListItem} from '@github-ui/list-view/ListItem'
import {GitHubAvatar} from '@github-ui/github-avatar'
import styles from './CopilotUserGrantAccessDialog.module.css'
import {ListView} from '@github-ui/list-view'
import {useState} from 'react'
import {SearchBar} from '@github-ui/licensing-common/components/SearchBar'
import {CopilotUserChangeAccessDialog} from './CopilotUserChangeAccessDialog'
import {useEnterpriseMemberSearch} from '../../hooks/use-enterprise-member-search'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'
import type {User} from '../../types'
import {XIcon} from '@primer/octicons-react'

export interface CopilotUserGrantAccessDialogProps {
  onDialogClose: () => void
}

export function CopilotUserGrantAccessDialog(props: CopilotUserGrantAccessDialogProps) {
  const [searchQuery, setSearchQuery] = useState('')
  const [selectedUsers, setSelectedUsers] = useState<User[]>([])
  const [showConfirmationDialog, setShowConfirmationDialog] = useState(false)
  const {basePath} = useNavigation()

  const {users: searchResults, loading: isLoading, isEmpty} = useEnterpriseMemberSearch(basePath, searchQuery)

  const handleUserSelect = (user: User) => {
    // Check if user is already selected
    if (!selectedUsers.some(selectedUser => selectedUser.id === user.id)) {
      setSelectedUsers([...selectedUsers, user])
    }
  }

  const handleUserRemove = (userId: number) => {
    setSelectedUsers(selectedUsers.filter(user => user.id !== userId))
  }

  const handleAddLicenses = () => {
    if (selectedUsers.length > 0) {
      setShowConfirmationDialog(true)
    }
  }

  const handleCloseConfirmationDialog = () => {
    setShowConfirmationDialog(false)
  }

  return (
    <>
      <Dialog
        title="Assign licenses"
        subtitle="Search for and select members to give Copilot Business access to. Users that already have access from an organization or team will only be charged for one license."
        onClose={props.onDialogClose}
        footerButtons={[
          {
            content: 'Cancel',
            buttonType: 'default',
            onClick: props.onDialogClose,
          },
          {
            content: 'Add licenses',
            buttonType: 'primary',
            onClick: handleAddLicenses,
            disabled: selectedUsers.length === 0,
          },
        ]}
      >
        <div className="flex-1" data-testid="licensing-copilot-user-grant-search">
          <SearchBar
            searchQuery={searchQuery}
            setSearchQuery={setSearchQuery}
            placeholder={'Search for members'}
            ariaLabel={'Search for members'}
          />
        </div>
        {searchQuery && (
          <ListView
            title={'Members'}
            className="border border-muted rounded-2 mb-3"
            data-testid="licensing-copilot-user-grant-access-list"
          >
            {isLoading ? (
              <ListItem title={<span />}>
                <div className={`text-center p-3 ${styles.stretchedText}`}>Loading members...</div>
              </ListItem>
            ) : isEmpty || searchResults.length === 0 ? (
              <ListItem title={<span />}>
                <div className={`text-center p-3 ${styles.stretchedText}`}>No members found matching your search.</div>
              </ListItem>
            ) : (
              searchResults.map(user => (
                <ListItem
                  key={user.id}
                  data-testid={`user-li-${user.login}`}
                  className={styles.clickableListItem}
                  title={
                    <Button variant="invisible" className={styles.userDetails} onClick={() => handleUserSelect(user)}>
                      <div className="d-flex align-items-center">
                        <GitHubAvatar src={user.avatarUrl} size={16} square className={styles.githubAvatar} />
                        <div className="ml-2">
                          <span className="text-bold">{user.login}</span>
                          <span className="text-small color-fg-muted ml-2">{user.name}</span>
                        </div>
                      </div>
                    </Button>
                  }
                />
              ))
            )}
          </ListView>
        )}

        {selectedUsers.length > 0 && (
          <div className="mb-1">
            <h3 className="mb-2 text-small text-bold">Selected members ({selectedUsers.length})</h3>
            <div className={styles.selectedUsersContainer}>
              {selectedUsers.map(user => (
                <div
                  key={`selected-${user.id}`}
                  data-testid={`selected-user-item-${user.login}`}
                  className={styles.selectedUserItem}
                >
                  <div className="d-flex align-items-center">
                    <GitHubAvatar src={user.avatarUrl} size={16} square className="mr-2" />
                    <span className="text-small text-bold mr-2">{user.login}</span>
                  </div>
                  <Button
                    variant="invisible"
                    size="small"
                    data-testid={`remove-user-${user.id}`}
                    className={styles.removeButton}
                    aria-label={`Remove ${user.login}`}
                    onClick={() => handleUserRemove(user.id)}
                  >
                    <XIcon size={12} />
                  </Button>
                </div>
              ))}
            </div>
          </div>
        )}
      </Dialog>

      {showConfirmationDialog && (
        <CopilotUserChangeAccessDialog
          users={selectedUsers.map(user => user.id)}
          downgrade={false}
          onClose={handleCloseConfirmationDialog}
        />
      )}
    </>
  )
}
