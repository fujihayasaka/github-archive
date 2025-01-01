import {UnderlineNav, Button} from '@primer/react'
import type {Organization, User} from '../types'
import {useCallback, useState} from 'react'
import {PeopleIcon, PersonIcon, OrganizationIcon} from '@primer/octicons-react'
import {CopilotOrganizationAccessList} from './organizations/CopilotOrganizationAccessList'
import {CopilotUserAccessList} from './users/CopilotUserAccessList'
import {CopilotOrganizationGrantAccessDialog} from './organizations/CopilotOrganizationGrantAccessDialog'
import {CopilotUserGrantAccessDialog} from './users/CopilotUserGrantAccessDialog'
import {SearchBar} from '@github-ui/licensing-common/components/SearchBar'
import styles from './CopilotAccessList.module.css'
import {useSearchParams} from 'react-router-dom'

export interface CopilotAccessListProps {
  enabledOrganizationCount: number
  enabledUserCount: number
  organizations: {
    withCopilotAccess: Organization[]
    withoutCopilotAccess: Organization[]
  }
  users: {
    withCopilotAccess: User[]
  }
  isCopilotUserFlagEnabled: boolean
  isCopilotEnterpriseTeamsFlagEnabled: boolean
}

export function CopilotAccessList(props: CopilotAccessListProps) {
  const [searchQuery, setSearchQuery] = useState('')
  const [searchParams, setSearchParams] = useSearchParams()
  const initialTab = searchParams.get('tab') || 'organizations'
  const [selectedTab, setSelectedTab] = useState(initialTab)

  const handleTabChange = (tab: string) => {
    setSelectedTab(tab)
    searchParams.set('tab', tab)
    setSearchParams(searchParams)
  }

  const [openGrantAccessDialog, setOpenGrantAccessDialog] = useState(false)

  // Filter the object based on the search query
  const searchQueryObjects =
    selectedTab === 'organizations'
      ? props.organizations.withCopilotAccess.filter(org => org.login.toLowerCase().includes(searchQuery.toLowerCase()))
      : selectedTab === 'users'
        ? props.users.withCopilotAccess.filter(user => user.login.toLowerCase().includes(searchQuery.toLowerCase()))
        : []

  const onDialogClose = useCallback(() => setOpenGrantAccessDialog(false), [])

  return (
    <div className="mb-3 pb-3" data-testid="licensing-copilot-access-list">
      <div className="pb-3">
        <UnderlineNav aria-label="Copilot Access Tabs">
          <UnderlineNav.Item
            aria-current={selectedTab === 'organizations' ? 'page' : undefined}
            onClick={() => handleTabChange('organizations')}
            counter={props.enabledOrganizationCount}
            icon={<OrganizationIcon size={16} />}
            data-testid="licensing-copilot-organization-access-tab"
          >
            Organizations
          </UnderlineNav.Item>
          {props.isCopilotEnterpriseTeamsFlagEnabled && (
            <UnderlineNav.Item
              aria-current={selectedTab === 'enterprise_teams' ? 'page' : undefined}
              onClick={() => handleTabChange('enterprise_teams')}
              counter={0}
              icon={<PeopleIcon size={16} />}
              data-testid="licensing-copilot-enterprise-teams-access-tab"
            >
              Enterprise Teams
            </UnderlineNav.Item>
          )}
          {props.isCopilotUserFlagEnabled && (
            <UnderlineNav.Item
              aria-current={selectedTab === 'users' ? 'page' : undefined}
              onClick={() => handleTabChange('users')}
              counter={props.enabledUserCount}
              icon={<PersonIcon size={16} />}
              data-testid="licensing-copilot-users-access-tab"
            >
              Users
            </UnderlineNav.Item>
          )}
        </UnderlineNav>
      </div>

      {/** Make this text variable based on the tab */}
      <p className={styles.tabDescription}>
        {selectedTab === 'organizations'
          ? 'Control which organizations will have access to Copilot Business and Copilot Enterprise. Organization admins will receive an email with setup instructions. Users assigned licenses across multiple organizations will only be billed once.'
          : selectedTab === 'enterprise_teams'
            ? 'Control which enterprise teams will have access to Copilot Business and Copilot Enterprise. Team admins will receive an email with setup instructions.'
            : 'Directly assign Copilot Business licenses to users. If they have access to both a Copilot Business license and a Copilot Enterprise license they will only be charged for the Copilot Enterprise license.'}
      </p>

      <div className="d-flex flex-row">
        <div className="flex-1">
          <SearchBar
            searchQuery={searchQuery}
            setSearchQuery={setSearchQuery}
            placeholder={
              selectedTab === 'organizations'
                ? 'Search or filter organizations'
                : selectedTab === 'enterprise_teams'
                  ? 'Search or filter enterprise teams'
                  : 'Search or filter members'
            }
            ariaLabel={
              selectedTab === 'organizations'
                ? 'Search or filter organizations'
                : selectedTab === 'enterprise_teams'
                  ? 'Search or filter enterprise teams'
                  : 'Search or filter members'
            }
          />
        </div>

        <div className="ml-2">
          <Button variant="primary" onClick={() => setOpenGrantAccessDialog(true)}>
            {selectedTab === 'users' ? 'Assign Licenses' : 'Grant Access'}
          </Button>
        </div>

        {openGrantAccessDialog === true && selectedTab === 'organizations' && (
          <CopilotOrganizationGrantAccessDialog
            organizations={props.organizations.withoutCopilotAccess}
            onDialogClose={onDialogClose}
          />
        )}
        {openGrantAccessDialog === true && props.isCopilotUserFlagEnabled && selectedTab === 'users' && (
          <CopilotUserGrantAccessDialog onDialogClose={onDialogClose} />
        )}
      </div>
      {selectedTab === 'organizations' && (
        <CopilotOrganizationAccessList
          setOpenGrantAccessDialog={setOpenGrantAccessDialog}
          organizations={searchQueryObjects as Organization[]}
          noOrgsWithCopilot={props.organizations.withCopilotAccess.length === 0}
        />
      )}
      {selectedTab === 'users' && (
        <CopilotUserAccessList
          setOpenGrantAccessDialog={setOpenGrantAccessDialog}
          users={searchQueryObjects as User[]}
          noUsersWithCopilot={props.users.withCopilotAccess.length === 0}
          isCopilotUserFlagEnabled={props.isCopilotUserFlagEnabled}
        />
      )}
    </div>
  )
}
