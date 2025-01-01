import {newEnterpriseRoleAssignmentPath} from '@github-ui/paths'
import {useState} from 'react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useNavigate} from '@github-ui/use-navigate'
import {ListView} from '@github-ui/list-view'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {ListItemActionBar} from '@github-ui/list-view/ListItemActionBar'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {ListViewDensityToggle} from '@github-ui/list-view/ListViewDensityToggle'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useDebounce} from '@github-ui/use-debounce'
import {
  PageHeader,
  Pagination,
  TextInput,
  Button,
  ActionList,
  ActionMenu,
  Text,
  Tooltip,
  Spinner,
  Label,
} from '@primer/react'
import {
  NoteIcon,
  PencilIcon,
  PeopleIcon,
  PersonIcon,
  SearchIcon,
  SortAscIcon,
  SortDescIcon,
  ListUnorderedIcon,
  TrashIcon,
  TypographyIcon,
  GlobeIcon,
} from '@primer/octicons-react'
import {Banner, Blankslate} from '@primer/react/experimental'
import TeamDeleteDialog from '../helpers/TeamDeleteDialog'
import {handleDelete} from '../helpers/handleDelete'
import {updateSearchParams} from '@github-ui/history'

import styles from '../styles/BusinessTeamsListView.module.css'

interface EnterpriseTeam {
  name: string
  id: number
  memberCount: number
  slug: string
  description: string
  viewTeamUrl: string
  editTeamUrl: string
  linkedToExternalGroup: boolean
}

export interface BusinessTeamsListViewPayload {
  enterpriseSlug: string
  enterpriseTeams: EnterpriseTeam[]
  enterpriseTeamsLimit: number
  enterpriseTeamsLimitReached: boolean
  createTeamUrl: string
  totalTeamsCount: number
  canCreateNewTeams: boolean
  isOwner: boolean
  meta: {
    filter: string
    page: number
    pageSize: number
    sortOption: string
    orderOption: string
  }
  viewerPermissions: {[permission: string]: boolean}
}

export function BusinessTeamsListView() {
  const payload = useRoutePayload<BusinessTeamsListViewPayload>()
  const enterpriseSlug = payload.enterpriseSlug
  const writeRoleAssignments = payload.viewerPermissions['write_enterprise_custom_enterprise_role']
  const navigate = useNavigate()

  const [searchParams, setSearchParams] = useState(
    () => new URLSearchParams(typeof window !== `undefined` ? window.location.search : ''),
  )
  const [metaData, setMetaData] = useState(payload.meta)
  const [searchQuery, setSearchQuery] = useState(searchParams.get('team') || '')
  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState(false)
  const [enterpriseTeams, setEnterpriseTeams] = useState(payload.enterpriseTeams)
  const [totalTeamsCount, setTotalTeamsCount] = useState(payload.totalTeamsCount)
  // eslint-disable-next-line @eslint-react/hooks-extra/prefer-use-state-lazy-initialization
  const [selectedTeams, setSelectedTeams] = useState<Set<{slug: string; name: string}>>(new Set())
  const [currentPage, setCurrentPage] = useState(payload.meta.page)
  const [loading, setLoading] = useState(false)

  const pageSize = metaData.pageSize
  const sortOption = metaData.sortOption
  const orderOption = metaData.orderOption
  const lastQueryFilter = metaData.filter
  const noTeamsExist = !lastQueryFilter && totalTeamsCount === 0

  const handleSearch = (searchValue: string) => {
    setSearchQuery(searchValue)
    setLoading(true)
    debounceFetchSearchData(searchValue)
  }

  const setSearchParam = (key: string, value: string) => {
    if (value === '') {
      searchParams.delete(key)
    } else {
      searchParams.set(key, value)
    }
    setSearchParams(searchParams)
    updateSearchParams(searchParams)
  }

  const debounceFetchSearchData = useDebounce((nextValue: string) => {
    setSearchParam('team', nextValue)
    paginate(1)
  }, 300)

  const handlePageChange = (newPage: number) => {
    setLoading(true)
    paginate(newPage)
  }

  const handleSortChange = (newSortOption: string) => {
    setSearchParam('sort', newSortOption)
    paginate(1)
  }

  const handleSortOrderChange = (newOrderOption: string) => {
    setSearchParam('order', newOrderOption)
    paginate(1)
  }

  const handleDeleteConfirmation = async () => {
    await handleDelete(enterpriseSlug, selectedTeams, () => {})
    setIsDeleteDialogOpen(false)
  }

  const paginate = async (page: number): Promise<void> => {
    setSearchParam('page', page.toString())
    setCurrentPage(page)

    const result = await verifiedFetchJSON(`/enterprises/${enterpriseSlug}/teams?${searchParams.toString()}`, {
      method: 'GET',
      headers: {Accept: 'application/json'},
    })
    const data = await result.json()

    setEnterpriseTeams(data.payload.enterpriseTeams)
    setTotalTeamsCount(data.payload.totalTeamsCount)
    setMetaData(data.payload.meta)
    setLoading(false)
  }

  return (
    <div>
      <div className="d-flex flex-justify-between align-items-center">
        <PageHeader>
          <PageHeader.TitleArea>
            <PageHeader.Title as="h1">Enterprise teams</PageHeader.Title>
          </PageHeader.TitleArea>
        </PageHeader>
        {!noTeamsExist &&
          payload.canCreateNewTeams &&
          (!payload.enterpriseTeamsLimitReached ? (
            <Button
              disabled={payload.enterpriseTeamsLimitReached}
              variant="primary"
              onClick={() => navigate(payload.createTeamUrl)}
            >
              Create Enterprise team
            </Button>
          ) : (
            <Tooltip
              text={`Cannot add more teams, you've reached the ${payload.enterpriseTeamsLimit}-team limit.`}
              direction="n"
            >
              <Button variant="default" inactive>
                Create Enterprise team
              </Button>
            </Tooltip>
          ))}
      </div>
      <div className="width-full border-bottom color-border-default mt-2" />
      <PageHeader.Description className="color-fg-muted mb-4">
        Teams are groups of members that reflect your company or group&apos;s structure with cascading access
        permissions and mentions.
      </PageHeader.Description>
      {noTeamsExist ? (
        <Blankslate spacious>
          <Blankslate.Visual>
            <PeopleIcon size={24} className="color-fg-muted mb-2" />
          </Blankslate.Visual>
          <Blankslate.Heading>You have no Enterprise teams</Blankslate.Heading>
          {payload.canCreateNewTeams && (
            <>
              <Blankslate.Description>Get started by creating a new Enterprise team.</Blankslate.Description>
              <Button
                className="mt-4"
                disabled={payload.enterpriseTeamsLimitReached}
                variant={payload.enterpriseTeamsLimitReached ? 'default' : 'primary'}
                onClick={() => navigate(payload.createTeamUrl)}
              >
                Create Enterprise team
              </Button>
            </>
          )}

          <Blankslate.SecondaryAction href="https://docs.github.com/organizations/organizing-members-into-teams/about-teams">
            Read more about Enterprise teams
          </Blankslate.SecondaryAction>
        </Blankslate>
      ) : (
        <div>
          <TextInput
            placeholder="Find a team..."
            leadingVisual={loading ? <Spinner size="small" className="mt-1" /> : <SearchIcon />}
            value={searchQuery}
            onChange={e => handleSearch(e.target.value)}
            aria-label="Search teams"
            sx={{width: '300px', mb: 3}}
            data-testid="search-input"
          />

          <ListView
            title="Enterprise teams"
            metadata={
              <ListViewMetadata
                title={`${totalTeamsCount} ${totalTeamsCount === 1 ? 'team' : 'teams'}`}
                densityToggle={
                  <ListViewDensityToggle localStorageVariantKey="enterprise-teams-list-density" sx={{mr: 2}} />
                }
                className={styles.ListViewMetadata_0}
              >
                <div className="d-flex flex-justify-end flex-items-center">
                  <ActionMenu>
                    <ActionMenu.Button
                      sx={{
                        border: 'none',
                        boxShadow: 'none',
                        color: 'fg.muted',
                        marginRight: 2,
                      }}
                      data-testid="filterDropdown-header"
                    >
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
                          selected={sortOption === 'Last added'}
                          onSelect={() => handleSortChange('Last added')}
                        >
                          <ListUnorderedIcon size={16} className="mr-2" />
                          Last added
                        </ActionList.Item>
                        <ActionList.Item selected={sortOption === 'Name'} onSelect={() => handleSortChange('Name')}>
                          <TypographyIcon size={16} className="mr-2" />
                          Name
                        </ActionList.Item>
                        <ActionList.Divider />
                        <ActionList.Item
                          selected={orderOption === 'Ascending'}
                          onSelect={() => handleSortOrderChange('Ascending')}
                        >
                          <SortAscIcon size={16} className="mr-2" />
                          Ascending
                        </ActionList.Item>
                        <ActionList.Item
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
            itemsListClassName={styles.ListView_0}
          >
            {payload.enterpriseTeamsLimitReached && (
              <Banner
                hideTitle
                title={`Enterprise Team limit ({payload.enterpriseTeamsLimit}) reached.`}
                data-testid="teams-limit-error"
                variant="info"
                style={{borderRadius: 0, borderTop: 0, borderLeft: 0, borderRight: 0}}
              >
                You&apos;ve reached the {payload.enterpriseTeamsLimit}-team limit. Remove existing teams to add more.
              </Banner>
            )}
            {enterpriseTeams.map(team => (
              <ListItem
                key={team.id}
                data-testid={`list-item-${team.id}`}
                title={
                  <ListItemTitle
                    value={team.name}
                    href={payload.isOwner ? team.viewTeamUrl : undefined}
                    headingClassName={`${styles.ListItemTitle_0}`}
                  >
                    {team.linkedToExternalGroup && (
                      <Label size="small" className={styles.idpGroupLabel}>
                        IdP group
                      </Label>
                    )}
                  </ListItemTitle>
                }
                metadata={
                  <ListItemMetadata alignment="right">
                    <PersonIcon size={16} />
                    <Text sx={{color: 'fg.muted'}}>{team.memberCount}</Text>
                  </ListItemMetadata>
                }
                secondaryActions={
                  payload.isOwner ? (
                    <ListItemActionBar
                      staticMenuActions={[
                        {
                          key: 'view-team',
                          render: () => {
                            return (
                              <ActionList.LinkItem href={team.viewTeamUrl}>
                                <ActionList.LeadingVisual>
                                  <NoteIcon />
                                </ActionList.LeadingVisual>
                                View
                              </ActionList.LinkItem>
                            )
                          },
                        },
                        {
                          key: 'assign-role',
                          render: () => {
                            if (writeRoleAssignments) {
                              return (
                                <ActionList.LinkItem
                                  href={newEnterpriseRoleAssignmentPath({slug: enterpriseSlug})}
                                  style={{width: 'max-content'}}
                                >
                                  <ActionList.LeadingVisual>
                                    <GlobeIcon />
                                  </ActionList.LeadingVisual>
                                  Assign Enterprise role
                                </ActionList.LinkItem>
                              )
                            }
                          },
                        },
                        {
                          key: 'edit-team',
                          render: () => {
                            return (
                              <ActionList.LinkItem href={team.editTeamUrl}>
                                <ActionList.LeadingVisual>
                                  <PencilIcon />
                                </ActionList.LeadingVisual>
                                Edit
                              </ActionList.LinkItem>
                            )
                          },
                        },
                        {
                          key: 'divider',
                          render: () => {
                            return <ActionList.Divider />
                          },
                        },
                        {
                          key: 'delete-team',
                          render: () => {
                            return (
                              <ActionList.LinkItem
                                variant="danger"
                                data-testid={`remove-team-${team.id}`}
                                onClick={() => {
                                  setSelectedTeams(new Set([{slug: team.slug, name: team.name}]))
                                  setIsDeleteDialogOpen(true)
                                }}
                              >
                                <ActionList.LeadingVisual sx={{color: 'danger.fg'}}>
                                  <TrashIcon />
                                </ActionList.LeadingVisual>
                                Delete
                              </ActionList.LinkItem>
                            )
                          },
                        },
                      ]}
                    />
                  ) : undefined
                }
                className={styles.ListItem_0}
              >
                <ListItemMainContent>
                  <ListItemDescription>{team.description}</ListItemDescription>
                </ListItemMainContent>
              </ListItem>
            ))}
            {lastQueryFilter && totalTeamsCount === 0 && (
              <Blankslate spacious>
                <Blankslate.Visual>
                  <SearchIcon size={24} className="color-fg-muted mb-2" />
                </Blankslate.Visual>
                <Blankslate.Heading>We couldn’t find any matching teams.</Blankslate.Heading>
                <Blankslate.Description>
                  No teams match your search criteria. Adjust your search or clear the filter to view all teams.
                </Blankslate.Description>
              </Blankslate>
            )}
          </ListView>

          {totalTeamsCount > pageSize && (
            <Pagination
              pageCount={Math.ceil(totalTeamsCount / pageSize)}
              currentPage={currentPage}
              onPageChange={(_, newPage) => handlePageChange(newPage)}
              showPages={{
                narrow: true,
              }}
            />
          )}
        </div>
      )}
      <TeamDeleteDialog
        isOpen={isDeleteDialogOpen}
        onClose={() => setIsDeleteDialogOpen(false)}
        onConfirm={handleDeleteConfirmation}
        selectedTeams={selectedTeams}
      />
    </div>
  )
}
