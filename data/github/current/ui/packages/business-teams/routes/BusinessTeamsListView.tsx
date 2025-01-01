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
  Link,
  Heading,
  ActionList,
  ActionMenu,
  Text,
  Spinner,
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
} from '@primer/octicons-react'
import {Blankslate} from '@primer/react/experimental'
import TeamDeleteDialog from '../helpers/TeamDeleteDialog'
import {handleDelete} from '../helpers/handleDelete'

import styles from '../styles/BusinessTeamsListView.module.css'

interface EnterpriseTeam {
  name: string
  id: number
  memberCount: number
  slug: string
  description: string
  viewTeamUrl: string
  editTeamUrl: string
}

export interface BusinessTeamsListViewPayload {
  enterpriseSlug: string
  enterpriseTeams: EnterpriseTeam[]
  enterpriseTeamsLimit: number
  enterpriseTeamsLimitReached: boolean
  createTeamUrl: string
  totalTeamsCount: number
  isOwner: boolean
  meta: {
    filter: string
    page: number
    pageSize: number
    sortOption: string
    orderOption: string
  }
}

export function BusinessTeamsListView() {
  const payload = useRoutePayload<BusinessTeamsListViewPayload>()
  const enterpriseSlug = payload.enterpriseSlug
  const navigate = useNavigate()

  const [searchParams, setSearchParams] = useState(
    () => new URLSearchParams(typeof window !== `undefined` ? window.location.search : ''),
  )
  const [metaData, setMetaData] = useState(payload.meta)
  const [searchQuery, setSearchQuery] = useState(searchParams.get('team') || '')
  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState(false)
  const [enterpriseTeams, setEnterpriseTeams] = useState(payload.enterpriseTeams)
  const [totalTeamsCount, setTotalTeamsCount] = useState(payload.totalTeamsCount)
  const [selectedTeams, setSelectedTeams] = useState<Set<string>>(new Set())
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
    window.history.replaceState({...window.history.state}, '', `?${searchParams.toString()}`)
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
        {!noTeamsExist && payload.isOwner && (
          <Button
            disabled={payload.enterpriseTeamsLimitReached}
            variant={payload.enterpriseTeamsLimitReached ? 'default' : 'primary'}
            onClick={() => navigate(payload.createTeamUrl)}
          >
            Create Enterprise team
          </Button>
        )}
      </div>
      <div className="width-full border-bottom color-border-default mt-2" />
      <PageHeader.Description className="color-fg-muted mb-4">
        Teams are groups of members that reflect your company or group&apos;s structure with cascading access
        permissions and mentions.
      </PageHeader.Description>
      {noTeamsExist ? (
        <div className="text-center mt-10">
          <PeopleIcon size="medium" className="mb-4" />
          <Heading as="h2" sx={{fontSize: 3}} className="mb-2">
            You have no Enterprise teams
          </Heading>
          {payload.isOwner && (
            <>
              <p className="color-fg-muted mb-3">Get started by creating a new Enterprise team.</p>
              <div className="d-flex flex-justify-center mb-3">
                <Button
                  disabled={payload.enterpriseTeamsLimitReached}
                  variant={payload.enterpriseTeamsLimitReached ? 'default' : 'primary'}
                  onClick={() => navigate(payload.createTeamUrl)}
                >
                  Create Enterprise team
                </Button>
              </div>
            </>
          )}
          <Link href="https://docs.github.com/organizations/organizing-members-into-teams/about-teams">
            Read more about Enterprise teams
          </Link>
        </div>
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
            autoFocus
            data-react-autofocus
          />

          <ListView
            title="Enterprise teams"
            metadata={
              <ListViewMetadata
                title={`${enterpriseTeams.length} ${enterpriseTeams.length === 1 ? 'Team' : 'Teams'}`}
                densityToggle={<ListViewDensityToggle sx={{mr: 2}} />}
                className={`${styles.ListViewMetadata_0} ${enterpriseTeams.length === 0 ? styles.noBottomBorder : ''}`}
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
            {enterpriseTeams.map(team => (
              <ListItem
                key={team.id}
                title={
                  <ListItemTitle
                    value={team.name}
                    href={payload.isOwner ? team.viewTeamUrl : undefined}
                    headingClassName={styles.ListItemTitle_0}
                  />
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
                                sx={{color: 'danger.fg'}}
                                onClick={() => {
                                  setSelectedTeams(new Set([team.slug]))
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
          </ListView>
          {lastQueryFilter && totalTeamsCount === 0 && (
            <Blankslate spacious className={styles.searchBlankSlate}>
              <Blankslate.Visual>
                <SearchIcon size={24} className="mb-3" />
              </Blankslate.Visual>
              <Blankslate.Heading>We couldn’t find any matching teams.</Blankslate.Heading>
              <Blankslate.Description>
                No teams match your search criteria. Adjust your search or clear the filter to view all teams.
              </Blankslate.Description>
            </Blankslate>
          )}
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
