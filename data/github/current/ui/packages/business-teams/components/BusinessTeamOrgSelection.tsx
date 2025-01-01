import {useState} from 'react'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {Button, FormControl} from '@primer/react'
import {OrganizationSelectPanel} from '../helpers/OrganizationSelectPanel'
import {OrganizationSelectionTypePanel} from '../helpers/OrganizationSelectionTypePanel'
import {OrganizationIcon, TasklistIcon, XIcon} from '@primer/octicons-react'
import styles from '../styles/BusinessTeamsCreateEditView.module.css'
import {Banner, Blankslate} from '@primer/react/experimental'
import pluralize from 'pluralize'
import {ListView} from '@github-ui/list-view'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import type {Organization} from '../types'

export function BusinessTeamOrgSelection({
  enterpriseSlug,
  organizationSelectionType,
  selectedOrganizations,
  selectedOrganizationsCount,
  allOrgsCount,
  enterpriseTeamsOrgAssignmentLimit,
  canSelectAllOrganizations,
  handleSelectionChange,
  handleSetSelectedOrganizations,
  preventEditOrganizations,
}: {
  enterpriseSlug: string
  organizationSelectionType: string
  selectedOrganizations: Organization[]
  selectedOrganizationsCount: number
  allOrgsCount: number
  enterpriseTeamsOrgAssignmentLimit: number
  canSelectAllOrganizations: boolean
  handleSelectionChange: (value: string) => void
  handleSetSelectedOrganizations: (Organization: Organization[]) => void
  preventEditOrganizations: boolean
}) {
  const [selectedOrganizationsState, setSelectedOrganizationsState] = useState<Organization[]>(selectedOrganizations)
  const orgLimitReached = selectedOrganizationsCount >= enterpriseTeamsOrgAssignmentLimit

  function handleAddOrganizations(addedOrganizations: Organization[]) {
    selectedOrganizations = [...selectedOrganizationsState, ...addedOrganizations]
    selectedOrganizations.sort((a, b) => (a.name || a.login).localeCompare(b.name || b.login))
    setSelectedOrganizationsState(selectedOrganizations)
    handleSetSelectedOrganizations(selectedOrganizations)
  }

  function removeOrganization(organization: Organization) {
    selectedOrganizations = selectedOrganizations.filter(org => org.id !== organization.id)
    setSelectedOrganizationsState(selectedOrganizations)
    handleSetSelectedOrganizations(selectedOrganizations)
  }

  return (
    <FormControl id="team-access">
      <FormControl.Label>Team access</FormControl.Label>
      <OrganizationSelectionTypePanel
        selectionType={organizationSelectionType}
        onSelectionChange={handleSelectionChange}
        enterpriseTeamsOrgAssignmentLimit={enterpriseTeamsOrgAssignmentLimit}
        allOrgsCount={allOrgsCount}
        canSelectAllOrganizations={canSelectAllOrganizations}
        selectedOrganizationCount={organizationSelectionType === 'all' ? allOrgsCount : selectedOrganizationsCount}
      />
      {organizationSelectionType === 'all' && !preventEditOrganizations ? (
        <div className="width-full mt-3">
          <Blankslate border spacious>
            <Blankslate.Visual>
              <OrganizationIcon size={24} className="color-fg-muted mb-2" />
            </Blankslate.Visual>
            <Blankslate.Heading>Your team will have access to all organizations</Blankslate.Heading>
            <Blankslate.Description>
              Your team will have access to all {allOrgsCount} organizations. You can change this access after creation
              in the team settings page.
            </Blankslate.Description>
          </Blankslate>
        </div>
      ) : organizationSelectionType === 'selected' && !preventEditOrganizations ? (
        <div className="width-full mt-3">
          <div className={`${styles.orgListView}`}>
            <ListView
              title="Organizations"
              metadata={
                <ListViewMetadata
                  title={`${selectedOrganizationsCount} ${pluralize('Organization', selectedOrganizationsCount)}`}
                  className={`${orgLimitReached ? '' : styles.noBottomBorder}`}
                >
                  <OrganizationSelectPanel
                    enterpriseSlug={enterpriseSlug}
                    alreadyAssignedOrgCount={0}
                    initialSelectedIds={selectedOrganizationsState.map(org => org.id)}
                    onOrganizationsAdded={handleAddOrganizations}
                    enterpriseTeamsOrgAssignmentLimit={enterpriseTeamsOrgAssignmentLimit}
                  />
                </ListViewMetadata>
              }
            >
              {orgLimitReached && (
                <Banner
                  title="Info"
                  hideTitle
                  description={`${enterpriseTeamsOrgAssignmentLimit}-organization limit reached. You can add more after team creation in the organizations section.`}
                  variant="info"
                  style={{
                    borderRadius: '0px',
                    borderTop: 'none',
                    borderLeft: 'none',
                    borderRight: 'none',
                  }}
                />
              )}
              {selectedOrganizationsState.map((organization, index) => {
                return (
                  <div
                    key={organization.id}
                    className={`d-flex flex-justify-between flex-items-center px-3 py-1 ${
                      index !== 0 || !orgLimitReached ? 'border-top' : ''
                    }`}
                  >
                    <div className="d-flex flex-items-center">
                      <GitHubAvatar
                        square
                        className="mr-2"
                        size={16}
                        src={organization.avatarUrl}
                        alt={organization.name || organization.login}
                      />
                      <div className={`ml-1 ${styles.textBold}`}>{organization.name || organization.login}</div>
                      <div className={`ml-2 ${styles.orgDescription}`}>{organization.description}</div>
                    </div>
                    <Button
                      variant="invisible"
                      aria-label={`Remove ${organization.name || organization.login} from the team`}
                      onClick={() => removeOrganization(organization)}
                      className={styles.removeOrgButton}
                    >
                      <XIcon />
                    </Button>
                  </div>
                )
              })}
            </ListView>
            {selectedOrganizationsCount === 0 && (
              <Blankslate spacious className="border-top">
                <Blankslate.Visual>
                  <TasklistIcon size={24} className="color-fg-muted mb-2" />
                </Blankslate.Visual>
                <Blankslate.Heading>Your team will have access to the selected organizations</Blankslate.Heading>
                <Blankslate.Description>
                  Choose the organizations where your team members will be added.
                </Blankslate.Description>
              </Blankslate>
            )}
          </div>
        </div>
      ) : null}
    </FormControl>
  )
}

BusinessTeamOrgSelection.displayName = 'BusinessTeamOrgSelection'
