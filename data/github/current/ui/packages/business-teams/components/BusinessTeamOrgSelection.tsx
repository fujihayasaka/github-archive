import {useState} from 'react'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {Button, FormControl} from '@primer/react'
import {OrganizationSelectPanel} from '../helpers/OrganizationSelectPanel'
import {OrganizationSelectionTypePanel} from '../helpers/OrganizationSelectionTypePanel'
import {OrganizationIcon, TasklistIcon, XIcon} from '@primer/octicons-react'
import styles from '../styles/BusinessTeamsCreateEditView.module.css'
import {Blankslate} from '@primer/react/experimental'
import pluralize from 'pluralize'
import {ListView} from '@github-ui/list-view'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import type {Organization} from '../types'

export function BusinessTeamOrgSelection({
  enterpriseSlug,
  organizationSelectionType,
  selectedOrganizations,
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
  allOrgsCount: number
  enterpriseTeamsOrgAssignmentLimit: number
  canSelectAllOrganizations: boolean
  handleSelectionChange: (value: string) => void
  handleSetSelectedOrganizations: (Organization: Organization[]) => void
  preventEditOrganizations: boolean
}) {
  const [selectedOrganizationsState, setSelectedOrganizationsState] = useState<Organization[]>(selectedOrganizations)
  const selectedOrgsLength = selectedOrganizationsState.length

  function handleAddOrganizations(addedOrganizations: Organization[]) {
    selectedOrganizations = [...selectedOrganizationsState, ...addedOrganizations]
    selectedOrganizations.sort((a, b) => a.name.localeCompare(b.name))
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
        selectedOrganizationCount={organizationSelectionType === 'all' ? allOrgsCount : selectedOrgsLength}
      />
      {organizationSelectionType === 'all' && !preventEditOrganizations ? (
        <div className="width-full mt-3">
          <Blankslate border spacious>
            <Blankslate.Visual>
              <OrganizationIcon size={24} />
            </Blankslate.Visual>
            <Blankslate.Heading>Your team will have access to all organizations</Blankslate.Heading>
            <Blankslate.Description>
              Your team will have access to all {allOrgsCount} organizations. <br /> You can change this access after
              creation in the team settings page.
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
                  title={`${selectedOrgsLength} ${pluralize('Organization', selectedOrgsLength)}`}
                  className={`${styles.textBold} ${styles.noBottomBorder}`}
                >
                  <OrganizationSelectPanel
                    enterpriseSlug={enterpriseSlug}
                    initialSelectedIds={selectedOrganizationsState.map(org => org.id)}
                    onOrganizationsAdded={handleAddOrganizations}
                    enterpriseTeamsOrgAssignmentLimit={enterpriseTeamsOrgAssignmentLimit}
                  />
                </ListViewMetadata>
              }
            >
              {selectedOrganizationsState.map(organization => {
                return (
                  <div
                    key={organization.id}
                    className={`d-flex flex-justify-between flex-items-center px-3 py-1 border-top`}
                  >
                    <div className="d-flex flex-items-center">
                      <GitHubAvatar
                        square
                        className="mr-2"
                        size={16}
                        src={organization.avatarUrl}
                        alt={organization.name}
                      />
                      <div className={`ml-1 ${styles.textBold}`}>{organization.name}</div>
                      <div className={`ml-2 ${styles.orgDescription}`}>{organization.description}</div>
                    </div>
                    <Button
                      variant="invisible"
                      aria-label={`Remove ${organization.name} from the team`}
                      onClick={() => removeOrganization(organization)}
                      className={styles.removeOrgButton}
                    >
                      <XIcon />
                    </Button>
                  </div>
                )
              })}
            </ListView>
            {selectedOrgsLength === 0 && (
              <Blankslate spacious className="border-top">
                <Blankslate.Visual>
                  <TasklistIcon size={24} />
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
