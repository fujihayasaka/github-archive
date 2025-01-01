import {ActionList, ActionMenu, Button, Heading, Checkbox, Pagination, Label} from '@primer/react'
import {ListView} from '@github-ui/list-view'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import type {Organization} from '../../types'
import styles from './CopilotOrganizationAccessList.module.css'
import pluralize from 'pluralize'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {clsx} from 'clsx'
import {CopilotOrganizationUpgradePlanDialog} from './CopilotOrganizationUpgradePlanDialog'
import {CopilotOrganizationDowngradePlanDialog} from './CopilotOrganizationDowngradePlanDialog'
import {capitalizePlan} from '../../utils/string-utils'
import {CopilotOrganizationBulkDisableAccessDialog} from './CopilotOrganizationBulkDisableAccessDialog'
import {useCheckboxSelection} from '@github-ui/licensing-common/hooks/useCheckboxSelection'
import {usePlanChangeConfirmationDialog} from '../../hooks/use-plan-change-confirmation-dialog'
import {CopilotPlanOptions} from '../../utils/copilot-plan-options'
import {usePagination} from '../../hooks/use-pagination'

export interface CopilotOrganizationAccessListProps {
  setOpenGrantAccessDialog: (arg0: boolean) => void
  organizations: Organization[]
  noOrgsWithCopilot: boolean
  pageSize?: number
}

// Ranking the plans to determine a downgrade/upgrade
const planRanks: Record<string, number> = {
  disabled: 0,
  business: 1,
  enterprise: 2,
}

export function CopilotOrganizationAccessList(props: CopilotOrganizationAccessListProps) {
  /** Dialog management */
  const {dialogState, openDialog, closeDialog} = usePlanChangeConfirmationDialog<{
    orgId?: number
    orgIds?: number[]
    oldPlan: string
    newPlan: string
  }>()

  const handlePlanChange = async (organization: Organization, option: {text: string; value: string}) => {
    if (organization.copilotPlan !== option.value) {
      const oldPlanRank = planRanks[organization.copilotPlan]
      const newPlanRank = planRanks[option.value]

      if (oldPlanRank === undefined || newPlanRank === undefined) {
        throw new Error(`Invalid plan detected`)
      }

      const dialogType = newPlanRank > oldPlanRank ? 'upgrade' : 'downgrade'
      openDialog(dialogType, {
        orgId: organization.id,
        oldPlan: organization.copilotPlan,
        newPlan: option.value,
      })
    }
  }

  const handleBulkPlanChange = async (organizations: Organization[], option: {text: string; value: string}) => {
    if (option.value === 'disabled') {
      openDialog('bulk-disable', {
        orgIds: organizations.map(org => org.id),
        oldPlan: '',
        newPlan: option.value,
      })
    }
  }

  const renderDialog = () => {
    if (!dialogState.data) return null

    switch (dialogState.type) {
      case 'upgrade':
        if (!dialogState.data.orgId) return null
        return (
          <CopilotOrganizationUpgradePlanDialog
            oldPlan={dialogState.data.oldPlan}
            newPlan={dialogState.data.newPlan}
            orgId={dialogState.data.orgId}
            closeDialog={closeDialog}
          />
        )

      case 'downgrade':
        if (!dialogState.data.orgId) return null
        return (
          <CopilotOrganizationDowngradePlanDialog
            oldPlan={dialogState.data.oldPlan}
            newPlan={dialogState.data.newPlan}
            orgId={dialogState.data.orgId}
            closeDialog={closeDialog}
          />
        )

      case 'bulk-disable':
        if (!dialogState.data.orgIds || dialogState.data.orgIds.length === 0) return null
        return <CopilotOrganizationBulkDisableAccessDialog orgIds={dialogState.data.orgIds} closeDialog={closeDialog} />

      default:
        return null
    }
  }

  /** Set up pagination */
  const {
    currentPage,
    totalPages,
    paginatedItems: paginatedOrganizations,
    navigateToPage,
  } = usePagination(props.organizations, {pageSize: props.pageSize || 20})

  /** Checkbox management for bulk org selection */
  const {
    selectedItems: selectedOrganizations,
    selectAll,
    handleSelectItem: handleSelectOrganization,
    handleSelectAll,
  } = useCheckboxSelection(paginatedOrganizations, (org: Organization) => org.id)

  // If no organizations with Copilot, show empty state instead of ListView
  if (props.noOrgsWithCopilot) {
    return (
      <>
        <div className={styles.grantAccess}>
          <Heading as="h3" className="mb-2">
            No organizations with access
          </Heading>
          <p className="color-fg-muted mb-3">
            Organizations that have been granted access to Copilot Business or Copilot Enterprise will be visible here
          </p>
          <div className="d-flex flex-justify-center mb-3">
            <Button variant="primary" onClick={() => props.setOpenGrantAccessDialog(true)}>
              Grant Access
            </Button>
          </div>
        </div>
      </>
    )
  }

  return (
    <>
      <ListView
        title={'Organizations'}
        metadata={
          <ListViewMetadata
            title={
              <div className={styles.metadataContainer}>
                <div className="d-flex align-items-center">
                  <Checkbox
                    checked={selectAll}
                    onChange={handleSelectAll}
                    aria-label="Select all organizations"
                    className="mr-2"
                  />
                  <span className="text-bold">
                    {selectedOrganizations.size > 0
                      ? `${selectedOrganizations.size} ${pluralize(
                          'organization',
                          selectedOrganizations.size,
                        )} selected`
                      : `${pluralize('organization', props.organizations.length, true)}`}
                  </span>
                </div>
              </div>
            }
            actionsLabel="Actions"
            actions={[
              {
                key: 'remove-bulk-access',
                render(isOverflowMenu) {
                  if (selectedOrganizations.size === 0) {
                    return <></>
                  }

                  const selectedOrgs = props.organizations.filter(org => selectedOrganizations.has(org.id))

                  return isOverflowMenu ? (
                    <ActionList.Item
                      id="button:remove-bulk-access"
                      onSelect={() => handleBulkPlanChange(selectedOrgs, {text: 'Disabled', value: 'disabled'})}
                    >
                      Remove access
                    </ActionList.Item>
                  ) : (
                    <Button
                      id="button:remove-bulk-access"
                      variant="danger"
                      className={styles.bulkDisableButton}
                      onClick={() => handleBulkPlanChange(selectedOrgs, {text: 'Disabled', value: 'disabled'})}
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
        data-testid="licensing-copilot-organization-access-list-view"
      >
        {paginatedOrganizations.map(organization => (
          <ListItem
            key={organization.id}
            title={
              <div className="d-flex flex-column pt-3">
                <div className="d-flex align-items-center">
                  <Checkbox
                    checked={selectedOrganizations.has(organization.id)}
                    onChange={() => handleSelectOrganization(organization.id)}
                    aria-label={`Select ${organization.login}`}
                    className="ml-3"
                  />
                  <GitHubAvatar src={organization.avatarUrl} size={16} square className={styles.githubAvatar} />
                  <div className="ml-2 flex-1">
                    <div className={`d-flex align-items-center ${styles.orgInfoContainer}`}>
                      <a href={organization.orgUrl} className={`text-bold ${styles.orgName}`}>
                        {organization.login}
                      </a>
                      {organization.expirationDate && (
                        <Label variant="attention" size="small" className="ml-2 text-nowrap">
                          Downgrades on {organization.expirationDate}
                        </Label>
                      )}
                    </div>
                    <p className={`${styles.orgMemberDetails} color-fg-muted text-small mb-0`}>
                      {`${pluralize('license', organization.licenseCount, true)} assigned`}
                    </p>
                  </div>
                </div>
              </div>
            }
          >
            <ListItemMainContent>
              <div className={styles.topRightButton}>
                <ActionMenu>
                  <ActionMenu.Button>
                    {organization.copilotPlan === 'disabled' ? (
                      <span className="color-fg-muted">Re-enable Copilot</span>
                    ) : (
                      <>
                        <span className="color-fg-muted">Copilot: </span>
                        {capitalizePlan(organization.copilotPlan)}
                      </>
                    )}
                  </ActionMenu.Button>
                  <ActionMenu.Overlay style={{minWidth: '225px'}}>
                    <ActionList selectionVariant="single">
                      {CopilotPlanOptions.map(option => (
                        <ActionList.Item
                          key={option.value}
                          selected={organization.copilotPlan === option.value}
                          onSelect={() => handlePlanChange(organization, option)}
                          data-testid={`org-copilot-plan-${organization.id}-${option.value
                            .replace('_', '-')
                            .toLowerCase()}`}
                        >
                          <span
                            className={clsx(option.value === 'disabled' ? 'color-fg-danger' : 'font-weight-normal')}
                          >
                            {option.text}
                          </span>
                          <p className={'color-fg-muted mt-1'}>{option.subtext}</p>
                        </ActionList.Item>
                      ))}
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

      {renderDialog()}
    </>
  )
}
