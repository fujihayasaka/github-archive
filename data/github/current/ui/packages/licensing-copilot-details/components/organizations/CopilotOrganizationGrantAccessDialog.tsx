import {ActionList, ActionMenu, Checkbox, Dialog, Pagination} from '@primer/react'
import type {Organization} from '../../types'
import {ListItem} from '@github-ui/list-view/ListItem'
import {GitHubAvatar} from '@github-ui/github-avatar'
import styles from './CopilotOrganizationGrantAccessDialog.module.css'
import {ListView} from '@github-ui/list-view'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import pluralize from 'pluralize'
import {useCheckboxSelection} from '@github-ui/licensing-common/hooks/useCheckboxSelection'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {clsx} from 'clsx'
import {useState} from 'react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useNavigate} from '@github-ui/use-navigate'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'
import {CopilotPlanOptions} from '../../utils/copilot-plan-options'
import {capitalizePlan} from '../../utils/string-utils'
import {Banner} from '@primer/react/experimental'
import {usePagination} from '../../hooks/use-pagination'

export interface CopilotOrganizationGrantAccessDialogProps {
  organizations: Organization[]
  onDialogClose: () => void
  pageSize?: number
}

export function CopilotOrganizationGrantAccessDialog(props: CopilotOrganizationGrantAccessDialogProps) {
  const {basePath} = useNavigation()
  const navigate = useNavigate()

  /* Use pagination */
  const {
    currentPage,
    totalPages,
    paginatedItems: paginatedOrganizations,
    navigateToPage,
  } = usePagination(props.organizations, {pageSize: props.pageSize || 10})

  const {
    selectedItems: selectedOrganizations,
    selectAll,
    handleSelectItem: handleSelectOrganization,
    handleSelectAll,
  } = useCheckboxSelection(paginatedOrganizations, (org: Organization) => org.id)

  const [Organizations, setOrganizations] = useState(props.organizations)
  const [showErrorBanner, setShowErrorBanner] = useState(false)

  const paginatedOrganizationsWithPlans = paginatedOrganizations.map(paginatedOrg => {
    const orgWithPlan = Organizations.find(org => org.id === paginatedOrg.id)
    return orgWithPlan || paginatedOrg
  })

  const handlePlanSelection = (organization: Organization, option: {text: string; value: string}) => {
    const updatedOrganizations = Organizations.map(org => {
      if (org.id === organization.id) {
        return {...org, newPlan: option.value}
      }
      return org
    })
    setOrganizations(updatedOrganizations)
  }

  const handleBulkEnablement = async () => {
    const planEnablementMap: Record<string, number[]> = {
      business: [],
      enterprise: [],
    }

    for (const org of Organizations) {
      if (org.newPlan !== org.copilotPlan) {
        planEnablementMap[org.newPlan]?.push(org.id)
      }
    }

    let anyErrors = false
    for (const [plan, orgs] of Object.entries(planEnablementMap)) {
      if (orgs.length > 0) {
        const formData = new FormData()
        formData.append('enablement', plan)
        for (const org of orgs) {
          formData.append('organizations[]', org.toString())
        }

        try {
          const response = await verifiedFetch(`${basePath}/settings/update_copilot_bulk_org_enablement`, {
            method: 'PUT',
            body: formData,
          })
          if (!response.ok) {
            anyErrors = true
          }
        } catch {
          anyErrors = true
        }
      }
    }
    if (anyErrors) {
      setShowErrorBanner(true)
    } else {
      navigate(`${basePath}/enterprise_licensing/copilot`)
    }
  }

  return (
    <>
      <Dialog
        title="Grant access to organizations"
        subtitle="Allow organizations to assign either Copilot Business or Copilot Enterprise licenses to their users"
        onClose={props.onDialogClose}
        footerButtons={[
          {buttonType: 'default', content: 'Cancel', onClick: props.onDialogClose},
          {
            buttonType: 'primary',
            content: 'Grant access',
            onClick: handleBulkEnablement,
          },
        ]}
      >
        {showErrorBanner && (
          <Banner
            title="Copilot Access Grant Error"
            hideTitle
            variant="critical"
            onDismiss={() => setShowErrorBanner(false)}
            className="mb-3"
            data-testid="copilot-grant-access-error-banner"
          >
            {'An error occurred while granting Copilot access to some organizations. Please refresh and try again.'}
          </Banner>
        )}
        <ListView
          title={'Organizations'}
          metadata={
            <ListViewMetadata
              title={
                <div className="d-flex align-items-center">
                  <Checkbox
                    checked={selectAll}
                    onChange={handleSelectAll}
                    aria-label="Select all organizations on this page"
                    className="mr-2"
                  />
                  <span>
                    {selectedOrganizations.size > 0
                      ? `${pluralize('organization', selectedOrganizations.size, true)} selected`
                      : pluralize('organization', props.organizations.length, true)}
                  </span>
                </div>
              }
              className="text-bold"
            />
          }
          className="border border-muted rounded-2"
          data-testid="licensing-copilot-organization-grant-access-list"
        >
          {paginatedOrganizationsWithPlans.map(organization => (
            <ListItem
              key={organization.id}
              data-testid={`org-li-${organization.login}`}
              title={
                <div className={`${styles.orgDetails}`}>
                  <div className="d-flex align-items-center">
                    <Checkbox
                      checked={selectedOrganizations.has(organization.id)}
                      onChange={() => handleSelectOrganization(organization.id)}
                      aria-label={`Select ${organization.login}`}
                      className="ml-3 mt-1"
                    />
                    <GitHubAvatar src={organization.avatarUrl} size={16} square className={styles.githubAvatar} />
                    <div className="ml-2">
                      <a href={organization.orgUrl} className="text-bold pb-2">
                        {organization.login}
                      </a>
                    </div>
                  </div>
                </div>
              }
            >
              {selectedOrganizations.has(organization.id) && (
                <div className="mb-0">
                  <ListItemMainContent>
                    <div className={styles.topRightButton}>
                      <ActionMenu>
                        <ActionMenu.Button data-testid={`org-copilot-plan-dropdown-${organization.login}`}>
                          <span className="color-fg-muted">{'Copilot: '}</span>
                          {capitalizePlan(organization.newPlan)}
                        </ActionMenu.Button>
                        <ActionMenu.Overlay style={{minWidth: '225px'}}>
                          <ActionList selectionVariant="single">
                            {CopilotPlanOptions.map(option => (
                              <ActionList.Item
                                key={option.value}
                                selected={organization.newPlan === option.value}
                                onSelect={() => handlePlanSelection(organization, option)}
                                data-testid={`org-copilot-plan-${organization.id}-${option.value
                                  .replace('_', '-')
                                  .toLowerCase()}`}
                              >
                                <span
                                  className={clsx(
                                    option.value === 'disabled' ? 'color-fg-danger' : 'font-weight-normal',
                                  )}
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
                </div>
              )}
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
      </Dialog>
    </>
  )
}
