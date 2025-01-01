import {ListView} from '@github-ui/list-view'
import {ListItem} from '@github-ui/list-view/ListItem'
import type {User} from '../../types'
import styles from './CopilotUserAccessList.module.css'
import pluralize from 'pluralize'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {ActionList, ActionMenu, Button, Checkbox, Heading, IconButton, Label, Pagination} from '@primer/react'
import {useCheckboxSelection} from '@github-ui/licensing-common/hooks/useCheckboxSelection'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {KebabHorizontalIcon} from '@primer/octicons-react'
import {CopilotUserChangeAccessDialog} from './CopilotUserChangeAccessDialog'
import {CopilotUserLicenseSummaryDialog} from './CopilotUserLicenseSummaryDialog'
import {useState} from 'react'
import {usePagination} from '../../hooks/use-pagination'

export interface CopilotUserAccessListProps {
  setOpenGrantAccessDialog: (arg0: boolean) => void
  users: User[]
  noUsersWithCopilot: boolean
  isCopilotUserFlagEnabled: boolean
  pageSize?: number
}

export function CopilotUserAccessList(props: CopilotUserAccessListProps) {
  const [selectedUserForDialog, setSelectedUserForDialog] = useState<number | number[] | null>(null)
  const [selectedUserForSummary, setSelectedUserForSummary] = useState<User | null>(null)

  const handleOpenLicenseRemovalDialog = (userId: number) => {
    setSelectedUserForDialog(userId)
  }

  const handleCloseLicenseRemovalDialog = () => {
    setSelectedUserForDialog(null)
  }

  const handleViewLicenseSummary = (user: User) => {
    setSelectedUserForSummary(user)
  }

  const handleCloseSummary = () => {
    setSelectedUserForSummary(null)
  }

  /** Set up pagination */
  const {
    currentPage,
    totalPages,
    paginatedItems: paginatedUsers,
    navigateToPage,
  } = usePagination(props.users, {pageSize: props.pageSize || 20})

  /** Checkbox management for bulk user selection - only for current page */
  const {
    selectedItems: selectedUsers,
    selectAll,
    handleSelectItem: handleSelectUser,
    handleSelectAll,
  } = useCheckboxSelection(paginatedUsers, (user: User) => user.id)

  if (props.noUsersWithCopilot) {
    return (
      <>
        <div className={styles.grantAccess}>
          <Heading as="h3" className="mb-2">
            No individual licenses
          </Heading>
          <p className="color-fg-muted mb-3">
            Enterprise members who have been granted Copilot Business will be visible here
          </p>
          <div className="d-flex flex-justify-center mb-3">
            <Button variant="primary" onClick={() => props.setOpenGrantAccessDialog(true)}>
              Assign licenses
            </Button>
          </div>
        </div>
      </>
    )
  }

  return (
    <>
      {props.isCopilotUserFlagEnabled && (
        <>
          <ListView
            title={'Users'}
            metadata={
              <ListViewMetadata
                title={
                  <div className={styles.metadataContainer}>
                    <div className="d-flex align-items-center">
                      <Checkbox
                        checked={selectAll}
                        onChange={handleSelectAll}
                        aria-label="Select all members on this page"
                        className="mr-2"
                      />
                      <span className="text-bold">
                        {selectedUsers.size > 0
                          ? `${selectedUsers.size} ${pluralize('member', selectedUsers.size)} selected`
                          : `${pluralize('member', props.users.length, true)}`}
                      </span>
                    </div>
                  </div>
                }
                actionsLabel="Actions"
                actions={[
                  {
                    key: 'remove-bulk-access',
                    render(isOverflowMenu) {
                      if (selectedUsers.size === 0) {
                        return <></>
                      }

                      const handleBulkRemoveAccess = () => {
                        setSelectedUserForDialog(Array.from(selectedUsers))
                      }

                      return isOverflowMenu ? (
                        <ActionList.Item id="button:remove-bulk-access" onSelect={handleBulkRemoveAccess}>
                          Remove access
                        </ActionList.Item>
                      ) : (
                        <Button
                          id="button:remove-bulk-access"
                          variant="danger"
                          className={styles.bulkDisableButton}
                          onClick={handleBulkRemoveAccess}
                        >
                          Remove access
                        </Button>
                      )
                    },
                  },
                ]}
              />
            }
            className="border border-muted rounded-2"
            data-testid="licensing-copilot-user-access-list-view"
          >
            {paginatedUsers.map((user: User) => (
              <ListItem
                key={user.id}
                title={
                  <div className="d-flex flex-column pt-3">
                    <div className="d-flex align-items-center flex-nowrap">
                      <Checkbox
                        checked={selectedUsers.has(user.id)}
                        onChange={() => handleSelectUser(user.id)}
                        aria-label={`Select ${user.login}`}
                        className="ml-3"
                      />
                      <GitHubAvatar src={user.avatarUrl} size={16} className={styles.githubAvatar} />
                      <div className={`ml-2 ${styles.userInfoContainer}`}>
                        <a href={user.userUrl} className="text-bold flex-nowrap">
                          {user.login}
                        </a>
                        <span className={`text-small color-fg-muted ml-2 ${styles.userName}`}>{user.name}</span>
                        {user.dominantLicense?.expirationDate && (
                          <Label variant="attention" size="small" className="ml-2 flex-shrink-0">
                            Expires on {user.dominantLicense.expirationDate}
                          </Label>
                        )}
                      </div>
                    </div>
                  </div>
                }
              >
                <ListItemMainContent>
                  <div className={styles.rightElipseButton}>
                    <ActionMenu>
                      <ActionMenu.Anchor>
                        <IconButton
                          icon={KebabHorizontalIcon}
                          variant="invisible"
                          aria-label="Show user license options"
                          data-testid={`kebab-icon-${user.id}`}
                        />
                      </ActionMenu.Anchor>
                      <ActionMenu.Overlay style={{minWidth: '225px'}}>
                        <ActionList>
                          <ActionList.Item
                            data-testid={`view-license-assignments-${user.id}`}
                            onSelect={() => handleViewLicenseSummary(user)}
                          >
                            <span className={'color-fg-bold'}>View license assignments</span>
                            <p className={'color-fg-muted mt-1'}>
                              See all license assignments this user receives from the enterprise, organizations, or
                              enterprise teams.
                            </p>
                          </ActionList.Item>
                          <ActionList.Item
                            data-testid={`unassign-license-${user.id}`}
                            onSelect={() => handleOpenLicenseRemovalDialog(user.id)}
                          >
                            <span className={'color-fg-danger'}>Unassign License</span>
                            <p className={'color-fg-muted mt-1'}>
                              Remove this user&apos;s license. They may still have access through an organization or
                              enterprise team.
                            </p>
                          </ActionList.Item>
                        </ActionList>
                      </ActionMenu.Overlay>
                    </ActionMenu>
                  </div>
                </ListItemMainContent>
              </ListItem>
            ))}
          </ListView>

          {totalPages > 1 && (
            <div className="mt-3 d-flex flex-justify-center">
              <Pagination
                currentPage={currentPage}
                pageCount={totalPages}
                onPageChange={(_, newPage) => navigateToPage(newPage)}
              />
            </div>
          )}
        </>
      )}

      {selectedUserForDialog !== null && (
        <CopilotUserChangeAccessDialog
          users={Array.isArray(selectedUserForDialog) ? selectedUserForDialog : [selectedUserForDialog]}
          downgrade
          onClose={handleCloseLicenseRemovalDialog}
        />
      )}
      {selectedUserForSummary !== null && (
        <CopilotUserLicenseSummaryDialog user={selectedUserForSummary} onClose={handleCloseSummary} />
      )}
    </>
  )
}
