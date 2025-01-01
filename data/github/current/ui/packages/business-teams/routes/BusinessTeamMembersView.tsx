import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import AddUserToTeamButton from '../components/AddUserToTeamButton'
import {ListView} from '@github-ui/list-view'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {useEffect, useState, useCallback} from 'react'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import pluralize from 'pluralize'
import {
  ActionList,
  ActionMenu,
  Button,
  FormControl,
  Link,
  Pagination,
  RelativeTime,
  Spinner,
  Stack,
  TextInput,
} from '@primer/react'
import {PeopleIcon, SearchIcon, SortAscIcon, SortDescIcon, XIcon} from '@primer/octicons-react'
import {Banner, Blankslate} from '@primer/react/experimental'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'
import {ListItemActionBar} from '@github-ui/list-view/ListItemActionBar'
import RemoveMembersDialog from '../components/RemoveMembersDialog'
import {handleMemberDelete} from '../helpers/HandleMemberDelete'
import {SafeHTMLBox, type SafeHTMLString} from '@github-ui/safe-html'
import type {EnterpriseTeam, ExternalGroup, User} from '../types'
import styles from '../styles/BusinessTeamMemberView.module.css'
import {ListViewDensityToggle} from '@github-ui/list-view/ListViewDensityToggle'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useDebounce} from '@github-ui/use-debounce'
import {BusinessTeamHeaderView} from '../components/BusinessTeamHeaderView'
import {pathingForTeam} from '../paths'
import {updateSearchParams} from '@github-ui/history'

export interface BusinessTeamMembersViewPayload {
  orgAssignmentsEnabled: boolean
  enterpriseSlug: string
  enterpriseTeamMembersLimit: number
  enterpriseTeam: EnterpriseTeam
  meta: {
    filter: string
    queryMemberCount: number
    page: number
    pageSize: number
    sortOption: string
    orderOption: string
    membersAllowedToAdd: number
    memberLimitReached: boolean
  }
  members: User[]
  viewerPermissions: {[permission: string]: boolean}
  externalGroup?: ExternalGroup
}

export function BusinessTeamMembersView() {
  const initialPayload = useRoutePayload<BusinessTeamMembersViewPayload>()
  // for all actual uses, stateful payload b/c page can change data and we need to keep view updating to reflect those changes
  const [payload, setPayload] = useState(initialPayload)
  const [searchParams, setSearchParams] = useState(() => new URLSearchParams(ssrSafeLocation.search))
  const [members, setMembers] = useState(payload.members || [])
  const [loading, setLoading] = useState(false)
  const [searchQuery, setSearchQuery] = useState(searchParams.get('query') || '')
  const [showCreatedBanner, setShowCreatedBanner] = useState(searchParams.get('created') === '1')
  const [titleContainerClassName, setTitleContainerClassName] = useState(styles.memberListViewTitleContainer)

  const enterpriseSlug = payload.enterpriseSlug
  const teamSlug = payload.enterpriseTeam.slug
  const navPathing = pathingForTeam(enterpriseSlug, teamSlug)
  const currentPage = payload.meta.page
  const sortOption = payload.meta.sortOption
  const orderOption = payload.meta.orderOption
  const queryMemberCount = payload.meta.queryMemberCount

  const setSearchParam = useCallback(
    (key: string, value: string) => {
      if (value === '') {
        searchParams.delete(key)
      } else {
        searchParams.set(key, value)
      }
      setSearchParams(searchParams)
      updateSearchParams(searchParams)
    },
    [searchParams],
  )

  const paginate = useCallback(
    async (page: number): Promise<void> => {
      setSearchParam('page', page.toString())
      const result = await verifiedFetchJSON(`${navPathing.base}?${searchParams.toString()}`, {
        method: 'GET',
        headers: {Accept: 'application/json'},
      })
      const data = (await result.json()) as BusinessTeamMembersViewPayload
      setMembers(data.members)
      setPayload(data)
      setLoading(false)
    },
    [navPathing.base, searchParams, setSearchParam],
  )

  useEffect(() => {
    if (showCreatedBanner) {
      setSearchParam('created', '')
    }
  }, [showCreatedBanner, setSearchParam])

  const handleSearch = (searchValue: string) => {
    setSearchQuery(searchValue)
    setLoading(true)
    debounceFetchSearchData(searchValue)
  }

  const debounceFetchSearchData = useDebounce((nextValue: string) => {
    setSearchParam('query', nextValue)
    paginate(1)
  }, 300)

  const handlePageChange = (newPage: number) => {
    setLoading(true)
    paginate(newPage)
  }

  const handleSortOrderChange = (newOrderOption: string) => {
    setSearchParam('order', newOrderOption)
    paginate(1)
  }

  const [flash, setFlash] = useState<SafeHTMLString>('' as SafeHTMLString)
  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState(false)
  const [selectedMembers, setSelectedMembers] = useState<User[]>([])

  const handleDeleteConfirmation = async () => {
    await handleMemberDelete(payload.enterpriseSlug, payload.enterpriseTeam.slug, selectedMembers, setFlash)
    setIsDeleteDialogOpen(false)
  }

  const handleDensityChange = (density: number) => {
    if (density === 1) {
      setTitleContainerClassName(styles.memberListViewTitleContainerCompact)
    } else {
      setTitleContainerClassName(styles.memberListViewTitleContainer)
    }
  }

  const refreshPage = async () => {
    setLoading(true)
    await paginate(1)

    // If we have fetched members, automatically transition out of the waiting state
    if (payload.members && payload.members.length > 0) {
      setShowCreatedBanner(false)
    }
  }

  return (
    <>
      {flash && (
        <Banner
          hideTitle
          title="error"
          data-testid="flash-error"
          variant="critical"
          className="mb-3"
          secondaryAction={
            <Button variant="invisible" onClick={() => setFlash('' as SafeHTMLString)} className={styles.closeButton}>
              <XIcon />
            </Button>
          }
        >
          <SafeHTMLBox html={flash} />
        </Banner>
      )}
      {showCreatedBanner && (
        <Banner
          hideTitle
          title="created"
          data-testid="flash-message-created"
          variant="success"
          className="mb-3"
          onDismiss={() => setShowCreatedBanner(false)}
        >
          Your new team has been successfully created.
        </Banner>
      )}

      <BusinessTeamHeaderView
        orgAssignmentsEnabled={payload.orgAssignmentsEnabled}
        viewerPermissions={payload.viewerPermissions}
        enterpriseSlug={payload.enterpriseSlug}
        enterpriseTeam={payload.enterpriseTeam}
        currentView="Members"
      />

      {/* Show waiting for sync message when newly created with external group */}
      {showCreatedBanner && payload.enterpriseTeam.linkedToExternalGroup ? (
        <Blankslate spacious>
          <Blankslate.Visual>
            <PeopleIcon size={24} className="color-fg-muted mb-2" />
          </Blankslate.Visual>
          <Blankslate.Heading>Waiting for members to sync</Blankslate.Heading>
          <Blankslate.Description>
            This team is linked to the identity provider group {payload.externalGroup?.displayName}. The members from
            this group are being synced and may take a few minutes to appear.
          </Blankslate.Description>
          <div className="mt-4 d-flex flex-justify-center">
            <Button onClick={refreshPage} data-testid="refresh-members-button">
              Refresh
            </Button>
          </div>
        </Blankslate>
      ) : payload.enterpriseTeam.totalMemberCount === 0 ? (
        <Blankslate spacious>
          <Blankslate.Visual>
            <PeopleIcon size={24} className="color-fg-muted mb-2" />
          </Blankslate.Visual>
          <Blankslate.Heading>Your team has no members</Blankslate.Heading>
          {payload.enterpriseTeam.linkedToExternalGroup ? (
            <Blankslate.Description>
              Your team is managed by an identity provider group with no members. To add members, you need to add
              members to the group in your Identity Provider. Alternatively, you can change the group or switch to
              manual member management in the team settings.
            </Blankslate.Description>
          ) : (
            <Blankslate.Description>
              Use the &apos;Add members&apos; button below to add members and start building your team.
            </Blankslate.Description>
          )}
          <div className="mt-4" />
          {!payload.enterpriseTeam.linkedToExternalGroup && (
            <AddUserToTeamButton
              data-testid="add-members"
              enterpriseSlug={enterpriseSlug}
              inactive={payload.meta.memberLimitReached}
              teamSlug={teamSlug}
              membersAllowedToAdd={payload.meta.membersAllowedToAdd}
              teamMembersLimit={payload.enterpriseTeamMembersLimit}
              addMembersToTable={() => {
                paginate(1)
              }}
            />
          )}
        </Blankslate>
      ) : (
        <div>
          <div className="mt-3 mb-3">
            <Stack direction="horizontal" justify="space-between">
              <FormControl>
                <FormControl.Label visuallyHidden>Member Search</FormControl.Label>
                <TextInput
                  className={styles.memberSearchInput}
                  leadingVisual={loading ? <Spinner size="small" className="mt-1" /> : SearchIcon}
                  placeholder="Find a member..."
                  value={searchQuery}
                  onChange={e => handleSearch(e.target.value.trim())}
                  data-testid="member-search-input"
                />
              </FormControl>
              {payload.externalGroup ? (
                <div
                  className="color-fg-muted text-small d-flex flex-items-center"
                  data-testid="identity-provider-group-info"
                >
                  Identity Provider Group{' '}
                  <Link
                    href={`/enterprises/${enterpriseSlug}/external_group_members/${payload.externalGroup.id}`}
                    className={`mx-1 ${styles.externalGroupLink}`}
                  >
                    {payload.externalGroup.displayName}
                  </Link>
                  updated&nbsp;
                  <RelativeTime data-testid="external-group-updated-time" datetime={payload.externalGroup.updatedAt} />.
                </div>
              ) : (
                <AddUserToTeamButton
                  data-testid="add-members"
                  enterpriseSlug={enterpriseSlug}
                  inactive={payload.meta.memberLimitReached}
                  teamSlug={teamSlug}
                  membersAllowedToAdd={payload.meta.membersAllowedToAdd}
                  teamMembersLimit={payload.enterpriseTeamMembersLimit}
                  addMembersToTable={() => {
                    paginate(1)
                  }}
                />
              )}
            </Stack>
          </div>

          <ListView
            title="Members"
            itemsListClassName={styles.memberListView}
            metadata={
              <ListViewMetadata
                title={`${queryMemberCount} ${pluralize('member', queryMemberCount)}`}
                className={styles.memberListViewMetadata}
                densityToggle={<ListViewDensityToggle onChange={handleDensityChange} className="mr-2" />}
              >
                <div className="d-flex flex-justify-end flex-items-center">
                  <ActionMenu>
                    <ActionMenu.Button className={styles.sortMenuButton} data-testid="filterDropdown-header">
                      {orderOption === 'Descending' ? (
                        <SortDescIcon size={16} className="mr-1" />
                      ) : (
                        <SortAscIcon size={16} className="mr-1" />
                      )}
                      {sortOption}
                    </ActionMenu.Button>
                    <ActionMenu.Overlay>
                      <ActionList selectionVariant="single">
                        <ActionList.Item
                          data-testid="sort-name-ascending"
                          selected={orderOption === 'Ascending'}
                          onSelect={() => handleSortOrderChange('Ascending')}
                        >
                          <SortAscIcon size={16} className="mr-2" />
                          Ascending
                        </ActionList.Item>
                        <ActionList.Item
                          data-testid="sort-name-descending"
                          selected={orderOption === 'Descending'}
                          onSelect={() => handleSortOrderChange('Descending')}
                        >
                          <SortDescIcon size={16} className="mr-2" />
                          Descending
                        </ActionList.Item>
                      </ActionList>
                    </ActionMenu.Overlay>
                  </ActionMenu>
                </div>
              </ListViewMetadata>
            }
          >
            {payload.meta.memberLimitReached && (
              <Banner
                hideTitle
                title={`Enterprise Team member limit ({payload.enterpriseTeamsLimit}) reached.`}
                data-testid="team-member-limit-error"
                variant="info"
                style={{
                  borderRadius: '0px',
                  borderTop: 'none',
                  borderLeft: 'none',
                  borderRight: 'none',
                }}
              >
                Your team has reached the {payload.enterpriseTeamMembersLimit} member limit. Remove existing members to
                add more.
              </Banner>
            )}
            {members.map(member => (
              <ListItem
                key={member.id}
                data-testid={`list-item-${member.id}`}
                title={
                  <ListItemTitle
                    data-testid="display-name"
                    value={member.profileName}
                    containerClassName={titleContainerClassName}
                    headingClassName={styles.memberListViewTitle}
                    href={`/enterprises/${enterpriseSlug}/people/${member.displayLogin}/organizations`}
                  />
                }
                secondaryActions={
                  !payload.enterpriseTeam.linkedToExternalGroup ? (
                    <ListItemActionBar
                      label="member actions"
                      staticMenuActions={[
                        {
                          key: 'remove-member',
                          render: () => {
                            return (
                              <ActionList.Item
                                variant="danger"
                                onSelect={() => {
                                  setFlash('' as SafeHTMLString)
                                  setSelectedMembers([member])
                                  setIsDeleteDialogOpen(true)
                                }}
                                data-testid={`remove-member-${member.id}`}
                              >
                                <ActionList.LeadingVisual>
                                  <XIcon />
                                </ActionList.LeadingVisual>
                                Remove
                              </ActionList.Item>
                            )
                          },
                        },
                      ]}
                    />
                  ) : undefined
                }
              >
                <ListItemLeadingContent>
                  <ListItemLeadingVisual className="mr-1">
                    <GitHubAvatar size={16} src={member.avatarUrl} alt="User avatar" />
                  </ListItemLeadingVisual>
                </ListItemLeadingContent>
                <ListItemMainContent>
                  <ListItemDescription className={`text-small ${styles.secondaryTextColor}`}>
                    {member.displayLogin}
                  </ListItemDescription>
                </ListItemMainContent>
              </ListItem>
            ))}
            {members.length === 0 && (
              <Blankslate spacious>
                <Blankslate.Visual>
                  <SearchIcon size={24} className="color-fg-muted mb-2" />
                </Blankslate.Visual>
                <Blankslate.Heading>We couldn’t find any matching members</Blankslate.Heading>
                <Blankslate.Description>
                  No members match your search criteria. Adjust your search or clear the filter to view all members.
                </Blankslate.Description>
              </Blankslate>
            )}
          </ListView>

          {queryMemberCount > payload.meta.pageSize && (
            <Pagination
              pageCount={Math.ceil(queryMemberCount / payload.meta.pageSize)}
              currentPage={currentPage}
              onPageChange={(_, newPage) => handlePageChange(newPage)}
              showPages={{
                narrow: true,
              }}
            />
          )}
        </div>
      )}

      <RemoveMembersDialog
        isOpen={isDeleteDialogOpen}
        onClose={() => setIsDeleteDialogOpen(false)}
        onConfirm={handleDeleteConfirmation}
        teamName={payload.enterpriseTeam.name}
        members={selectedMembers}
      />
    </>
  )
}
