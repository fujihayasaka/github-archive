import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {BusinessTeamHeaderView} from '../components/BusinessTeamHeaderView'
import {Banner, Blankslate} from '@primer/react/experimental'
import {OrganizationIcon, XIcon, SortDescIcon, SortAscIcon} from '@primer/octicons-react'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {ListView} from '@github-ui/list-view'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ListViewDensityToggle} from '@github-ui/list-view/ListViewDensityToggle'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import type {EnterpriseTeam, Organization} from '../types'
import pluralize from 'pluralize'
import styles from '../styles/BusinessTeamOrganizationsView.module.css'
import {useState} from 'react'
import {ListItemActionBar} from '@github-ui/list-view/ListItemActionBar'
import {ActionList, Button, ActionMenu, Pagination} from '@primer/react'
import {SafeHTMLBox, type SafeHTMLString} from '@github-ui/safe-html'
import OrganizationDeleteDialog from '../components/OrganizationDeleteDialog'
import {handleOrgDelete} from '../helpers/HandleOrgDelete'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {pathingForTeam} from '../paths'
import {OrganizationSelectPanel} from '../helpers/OrganizationSelectPanel'
import {updateSearchParams} from '@github-ui/history'

export interface BusinessTeamOrganizationsViewPayload {
  orgAssignmentsEnabled: boolean
  enterpriseTeamsOrgAssignmentLimit: number
  viewerPermissions: {[permission: string]: boolean}
  enterpriseSlug: string
  enterpriseTeam: EnterpriseTeam
  organizations?: Organization[]
  meta: {
    pageSize: number
    page: number
  }
}

export function BusinessTeamOrganizationsView() {
  const payload = useRoutePayload<BusinessTeamOrganizationsViewPayload>()
  const [organizationSelectionType, setOrganizationSelectionType] = useState(
    payload.enterpriseTeam.organizationSelectionType,
  )
  const [orgs, setOrgs] = useState<Organization[]>(payload.organizations || [])
  const [titleContainerClassName, setTitleContainerClassName] = useState(styles.organizationListViewTitleContainer)
  const [totalOrgCount, setTotalOrgCount] = useState(payload.enterpriseTeam.totalOrganizationCount)
  const {enterpriseTeam, ...restPayload} = payload
  const updatedTeam = {...enterpriseTeam, totalOrganizationCount: totalOrgCount}
  const [flash, setFlash] = useState<SafeHTMLString>('' as SafeHTMLString)
  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState(false)
  const [selectedOrgs, setSelectedOrgs] = useState<Organization[]>([])
  const [searchParams, setSearchParams] = useState(
    () => new URLSearchParams(typeof window !== `undefined` ? window.location.search : ''),
  )
  const [currentPage, setCurrentPage] = useState(payload.meta.page)
  const [orderOption, setOrderOption] = useState('Ascending')
  const sortOption = 'Name'
  const navPathing = pathingForTeam(payload.enterpriseSlug, payload.enterpriseTeam.slug)

  const handleDeleteConfirmation = async () => {
    const response = await handleOrgDelete(payload.enterpriseSlug, payload.enterpriseTeam.slug, selectedOrgs, setFlash)
    setIsDeleteDialogOpen(false)

    if (response && response.message) {
      paginate(1)
    }
  }

  const paginate = async (page: number): Promise<void> => {
    setSearchParam('page', page.toString())
    const result = await verifiedFetchJSON(`${navPathing.base}/organizations?${searchParams.toString()}`, {
      method: 'GET',
      headers: {Accept: 'application/json'},
    })
    const data = (await result.json()).payload as BusinessTeamOrganizationsViewPayload

    setCurrentPage(page)
    setOrgs(data?.organizations || [])
    setTotalOrgCount(data?.enterpriseTeam.totalOrganizationCount || 0)
  }

  const handleSortOrderChange = (newOrderOption: string) => {
    setOrderOption(newOrderOption)
    setSearchParam('order', newOrderOption)
    paginate(1)
  }

  const handlePageChange = (newPage: number) => {
    paginate(newPage)
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

  const handleDensityChange = (density: number) => {
    if (density === 1) {
      setTitleContainerClassName(styles.organizationListViewTitleContainerCompact)
    } else {
      setTitleContainerClassName(styles.organizationListViewTitleContainer)
    }
  }

  const showBlankSlate =
    organizationSelectionType === 'all' ||
    organizationSelectionType === 'disabled' ||
    (organizationSelectionType === 'selected' && totalOrgCount === 0)

  function handleAddOrganizations() {
    paginate(1)
    if (organizationSelectionType === 'disabled') {
      setOrganizationSelectionType('selected')
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
            <Button variant="invisible" onClick={() => setFlash('' as SafeHTMLString)}>
              <XIcon />
            </Button>
          }
        >
          <SafeHTMLBox html={flash} />
        </Banner>
      )}

      <BusinessTeamHeaderView {...restPayload} enterpriseTeam={updatedTeam} currentView="Organizations" />

      {showBlankSlate ? (
        <Blankslate spacious>
          <Blankslate.Visual>
            <OrganizationIcon size={24} className="color-fg-muted mb-2" />
          </Blankslate.Visual>
          {organizationSelectionType === 'all' ? (
            <>
              <Blankslate.Heading>
                Your team has access to all organizations in {payload.enterpriseSlug}.
              </Blankslate.Heading>
              <Blankslate.Description>
                Your team currently has access to all {totalOrgCount} organizations. To limit access to specific
                organizations, update the team access in the settings page.
              </Blankslate.Description>
              <Button
                className="mt-4"
                as="a"
                href={`/enterprises/${payload.enterpriseSlug}/teams/${payload.enterpriseTeam.slug}/edit`}
              >
                Update settings
              </Button>
              <Blankslate.SecondaryAction href={`/enterprises/${payload.enterpriseSlug}/organizations`}>
                See all organizations
              </Blankslate.SecondaryAction>
            </>
          ) : (
            <>
              <Blankslate.Heading>Your team doesn&apos;t have access to any organizations.</Blankslate.Heading>
              <Blankslate.Description>
                Use the &apos;Add organizations&apos; button below to add organizations to your team.
              </Blankslate.Description>
              <div className="d-flex justify-center align-items-center mt-4">
                <OrganizationSelectPanel
                  enterpriseSlug={payload.enterpriseSlug}
                  alreadyAssignedOrgCount={totalOrgCount}
                  initialSelectedIds={[]}
                  onOrganizationsAdded={handleAddOrganizations}
                  enterpriseTeamsOrgAssignmentLimit={payload.enterpriseTeamsOrgAssignmentLimit}
                  teamSlug={payload.enterpriseTeam.slug}
                />
              </div>
              <Blankslate.SecondaryAction
                href={`/enterprises/${payload.enterpriseSlug}/teams/${payload.enterpriseTeam.slug}/edit`}
              >
                Update settings
              </Blankslate.SecondaryAction>
            </>
          )}
        </Blankslate>
      ) : (
        <>
          <div className={`d-flex flex-justify-end mt-3`}>
            <OrganizationSelectPanel
              enterpriseSlug={payload.enterpriseSlug}
              alreadyAssignedOrgCount={totalOrgCount}
              initialSelectedIds={[]}
              onOrganizationsAdded={handleAddOrganizations}
              enterpriseTeamsOrgAssignmentLimit={payload.enterpriseTeamsOrgAssignmentLimit}
              teamSlug={payload.enterpriseTeam.slug}
            />
          </div>

          <div className="mt-3">
            <ListView
              title="Organizations"
              itemsListClassName={styles.organizationListView}
              metadata={
                <ListViewMetadata
                  title={`${totalOrgCount} ${pluralize('organization', totalOrgCount)}`}
                  className={`${styles.organizationListViewMetadata} ${orgs.length === 0 ? styles.noBottomBorder : ''}`}
                  densityToggle={<ListViewDensityToggle onChange={handleDensityChange} className="mr-2" />}
                >
                  {
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
                  }
                </ListViewMetadata>
              }
            >
              {totalOrgCount >= payload.enterpriseTeamsOrgAssignmentLimit && (
                <Banner
                  title="Info"
                  hideTitle
                  description={`Your team has reached the ${payload.enterpriseTeamsOrgAssignmentLimit} organization limit. Remove existing organizations to add more.`}
                  variant="info"
                  style={{
                    borderRadius: '0px',
                    borderTop: 'none',
                    borderLeft: 'none',
                    borderRight: 'none',
                  }}
                />
              )}
              {orgs.map(org => (
                <ListItem
                  key={org.id}
                  data-testid={`list-item-${org.id}`}
                  title={
                    <ListItemTitle
                      value={org.name || org.login}
                      containerClassName={titleContainerClassName}
                      headingClassName={styles.organizationListViewTitle}
                      href={`/${org.login}`}
                    />
                  }
                  secondaryActions={
                    <ListItemActionBar
                      label="organization actions"
                      staticMenuActions={[
                        {
                          key: 'remove-org',
                          render: () => {
                            return (
                              <ActionList.Item
                                variant="danger"
                                onSelect={() => {
                                  setFlash('' as SafeHTMLString)
                                  setSelectedOrgs([org])
                                  setIsDeleteDialogOpen(true)
                                }}
                                data-testid={`remove-org-${org.id}`}
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
                  }
                >
                  <ListItemLeadingContent>
                    <ListItemLeadingVisual className="mr-1">
                      <GitHubAvatar square size={16} src={org.avatarUrl} alt="Organization avatar" />
                    </ListItemLeadingVisual>
                  </ListItemLeadingContent>
                  <ListItemMainContent>
                    <ListItemDescription className={`text-small ${styles.secondaryTextColor}`}>
                      {org.description}
                    </ListItemDescription>
                  </ListItemMainContent>
                </ListItem>
              ))}
            </ListView>
            {totalOrgCount > payload.meta.pageSize && (
              <Pagination
                data-testid="pagination"
                pageCount={Math.ceil(totalOrgCount / payload.meta.pageSize)}
                currentPage={currentPage}
                onPageChange={(_, newPage) => handlePageChange(newPage)}
                showPages={{
                  narrow: true,
                }}
              />
            )}
          </div>
          <OrganizationDeleteDialog
            isOpen={isDeleteDialogOpen}
            onClose={() => setIsDeleteDialogOpen(false)}
            onConfirm={handleDeleteConfirmation}
            teamName={payload.enterpriseTeam.name}
            selectedOrganizations={selectedOrgs}
          />
        </>
      )}
    </>
  )
}
