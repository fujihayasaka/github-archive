import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {BusinessTeamHeaderView} from '../components/BusinessTeamHeaderView'
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

export interface BusinessTeamOrganizationsViewPayload {
  orgAssignmentsEnabled: boolean
  enterpriseSlug: string
  enterpriseTeam: EnterpriseTeam
  organizations: Organization[]
}

export function BusinessTeamOrganizationsView() {
  const payload = useRoutePayload<BusinessTeamOrganizationsViewPayload>()
  const [orgs, _] = useState<Organization[]>(payload.organizations)
  const [titleContainerClassName, setTitleContainerClassName] = useState(styles.organizationListViewTitleContainer)
  const totalOrgCount = payload.enterpriseTeam.totalOrganizationCount
  // const [searchParams, setSearchParams] = useState(
  //   () => new URLSearchParams(typeof window !== `undefined` ? window.location.search : ''),
  // )
  // const [orderOption, setOrderOption] = useState('Descending')
  // const sortOption = 'Name'

  // const paginate = async (page: number): Promise<void> => {
  //   setSearchParam('page', page.toString())

  //   const result = await verifiedFetchJSON(`${navPathing.base}?${searchParams.toString()}`, {
  //     method: 'GET',
  //     headers: {Accept: 'application/json'},
  //   })
  //   const data = (await result.json()) as BusinessTeamMembersViewPayload

  //   setMembers(data.members)
  //   setPayload(data)
  //   setLoading(false)
  // }

  // const handleSortOrderChange = (newOrderOption: string) => {
  //   setSearchParam('order', newOrderOption)
  //   paginate(1)
  // }

  // const setSearchParam = (key: string, value: string) => {
  //   const newSearchParams = new URLSearchParams(searchParams.toString())
  //   if (value === '') {
  //     newSearchParams.delete(key)
  //   } else {
  //     newSearchParams.set(key, value)
  //   }
  //   setSearchParams(newSearchParams)
  //   window.history.replaceState({...window.history.state}, '', `?${newSearchParams.toString()}`)
  // }

  const handleDensityChange = (density: number) => {
    if (density === 1) {
      setTitleContainerClassName(styles.organizationListViewTitleContainerCompact)
    } else {
      setTitleContainerClassName(styles.organizationListViewTitleContainer)
    }
  }

  return (
    <>
      <BusinessTeamHeaderView
        orgAssignmentsEnabled={payload.orgAssignmentsEnabled}
        enterpriseSlug={payload.enterpriseSlug}
        enterpriseTeam={payload.enterpriseTeam}
        currentView="Organizations"
      />

      <div className="mt-3">
        <ListView
          title="Organizations"
          itemsListClassName={styles.organizationListView}
          metadata={
            <ListViewMetadata
              title={`${totalOrgCount} ${pluralize('Organization', totalOrgCount)}`}
              className={`${styles.organizationListViewMetadata} ${orgs.length === 0 ? styles.noBottomBorder : ''}`}
              densityToggle={<ListViewDensityToggle onChange={handleDensityChange} className="mr-2" />}
            >
              {/* <div className="d-flex flex-justify-end flex-items-center">
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
              </div> */}
            </ListViewMetadata>
          }
        >
          {orgs.map(org => (
            <ListItem
              key={org.id}
              data-testid={`list-item-${org.id}`}
              title={
                <ListItemTitle
                  data-testid="list-view-item-title-container"
                  value={org.name}
                  containerClassName={titleContainerClassName}
                  headingClassName={styles.organizationListViewTitle}
                  href={`/${org.name}`}
                />
              }
            >
              <ListItemLeadingContent>
                <ListItemLeadingVisual className="mr-1">
                  <GitHubAvatar size={16} src={org.avatarUrl} alt="Organization avatar" />
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
      </div>
    </>
  )
}
