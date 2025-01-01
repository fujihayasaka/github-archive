import {ActionList, ActionMenu, PageHeader, Button, Tooltip} from '@primer/react'
import {useState, useCallback, useRef} from 'react'
import {GoalIcon, IssueDraftIcon, TriangleDownIcon} from '@primer/octicons-react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {OrgAlertsFilter} from '../components/OrgAlertsFilter'
import {LimitedRepoWarning} from '../components/LimitedRepoWarning'
import {useAlertsParams} from '../hooks/use-alerts-params'
import {useAlertFilterProviders} from '../hooks/use-alert-filter-providers'
import {
  securityCampaignOrgCampaignPath,
  securityCampaignOrgCampaignPublishPath,
  securityCampaignOrgCampaignsPath,
} from '@github-ui/paths'
import {useCreateDraftSecurityCampaignMutation} from '../hooks/use-create-draft-security-campaign-mutation'
import type {User} from '@github-ui/security-campaigns-shared/types/user'
import {useNavigate} from '@github-ui/use-navigate'
import {OrgDraftSecurityCampaignAlerts} from '../components/OrgDraftSecurityCampaignAlerts'
import {OrgSecurityCampaignBreadcrumbs} from '../components/OrgSecurityCampaignBreadcrumbs'
import {NewCampaignNoFiltersBlankslate} from '../components/NewCampaignNoFiltersBlankslate'
import {UpsertDraftSecurityCampaignFormDialog} from '../components/UpsertDraftSecurityCampaignFormDialog'
import type {SecurityCampaignForm} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import type {AdvancedFilterDialogRef} from '@github-ui/filter'

export type OrgSecurityCampaignNewPayload = {
  organizationLogin: string
  currentUser: User
  orgDraftCampaignsCount: number
  maxDraftCampaigns: number
  orgOpenCampaignsCount: number
  maxOpenCampaigns: number
  maxManagers: number
  customPropertyNames: string[]
  showNewAutofixFilters: boolean
  showIncompleteDataWarning: boolean
  incompleteDataWarningDocHref: string
  campaignName: string | null
  campaignDescription: string | null
}

export const OrgSecurityCampaignNew = () => {
  const {
    organizationLogin,
    currentUser,
    orgDraftCampaignsCount,
    maxDraftCampaigns,
    orgOpenCampaignsCount,
    maxOpenCampaigns,
    maxManagers,
    customPropertyNames,
    showNewAutofixFilters,
    showIncompleteDataWarning,
    incompleteDataWarningDocHref,
    campaignName,
    campaignDescription,
  } = useRoutePayload<OrgSecurityCampaignNewPayload>()
  const maxDraftCampaignsReached = orgDraftCampaignsCount >= maxDraftCampaigns
  const maxOpenCampaignsReached = orgOpenCampaignsCount >= maxOpenCampaigns

  const navigate = useNavigate()

  const [isSaveDialogOpen, setIsSaveDialogOpen] = useState(false)
  const {query, cursor, group, onQueryChange, onCursorChange, onGroupChange, onStateFilterChange} = useAlertsParams({
    initialQuery: '',
    initialGroup: 'none',
  })

  const filterProviders = useAlertFilterProviders({
    organizationLogin,
    showNewAutofixFilters,
    customPropertyNames,
  })

  const {mutate, isPending, isSuccess, error, reset} = useCreateDraftSecurityCampaignMutation(organizationLogin)

  const createCampaign = useCallback(
    (campaign: SecurityCampaignForm) => {
      mutate(
        {
          campaignName: campaign.name,
          campaignDescription: campaign.description,
          query,
          campaignManagers: campaign.managers.map(user => user.id),
          campaignTeamManagers: campaign.teamManagers.map(team => team.id),
          campaignContactLink: campaign.contactLink,
        },
        {
          onSuccess: response => {
            navigate(
              securityCampaignOrgCampaignPath({
                org: organizationLogin,
                securityCampaignNumber: response.campaignNumber,
              }),
            )
          },
        },
      )
    },
    [mutate, navigate, organizationLogin, query],
  )

  const advancedFilterDialogRef = useRef<AdvancedFilterDialogRef>(null)
  const onAddFiltersClick = useCallback(() => {
    advancedFilterDialogRef.current?.toggleAdvancedFilterDialog(true)
  }, [])

  // Show a loading state when we're redirecting to the new campaign
  const isLoading = isPending || isSuccess
  const isValid = query.trim() !== ''

  return (
    <>
      {isSaveDialogOpen && (
        <UpsertDraftSecurityCampaignFormDialog
          organizationLogin={organizationLogin}
          currentUser={currentUser}
          setIsOpen={setIsSaveDialogOpen}
          submitForm={createCampaign}
          isPending={isLoading}
          formError={error}
          resetForm={reset}
          maxManagers={maxManagers}
          campaignName={campaignName}
          campaignDescription={campaignDescription}
        />
      )}
      <OrgSecurityCampaignBreadcrumbs
        href={securityCampaignOrgCampaignsPath({org: organizationLogin})}
        text="Campaigns"
        selectedText="Select filters"
      />
      <PageHeader aria-label="Create a new campaign">
        <PageHeader.TitleArea>
          <PageHeader.Title>Create a new campaign</PageHeader.Title>
        </PageHeader.TitleArea>
        <PageHeader.Actions>
          {isValid ? (
            <ActionMenu>
              <ActionMenu.Button variant="primary" loading={isLoading}>
                Save as
              </ActionMenu.Button>
              <ActionMenu.Overlay width="medium">
                <ActionList>
                  <ActionList.Item
                    onSelect={() => setIsSaveDialogOpen(true)}
                    loading={isLoading}
                    disabled={maxDraftCampaignsReached || isLoading}
                    inactiveText={
                      maxDraftCampaignsReached
                        ? `Limit of ${maxDraftCampaigns} draft campaigns has been reached`
                        : undefined
                    }
                  >
                    <ActionList.LeadingVisual>
                      <IssueDraftIcon />
                    </ActionList.LeadingVisual>
                    Draft campaign
                  </ActionList.Item>
                  <ActionList.Item
                    onSelect={() =>
                      navigate(
                        securityCampaignOrgCampaignPublishPath({
                          org: organizationLogin,
                          query,
                          campaignName: campaignName || undefined,
                          campaignDescription: campaignDescription || undefined,
                        }),
                      )
                    }
                    loading={isLoading}
                    disabled={maxOpenCampaignsReached || isLoading}
                    inactiveText={
                      maxOpenCampaignsReached ? `Limit of ${maxOpenCampaigns} campaigns has been reached` : undefined
                    }
                  >
                    <ActionList.LeadingVisual>
                      <GoalIcon />
                    </ActionList.LeadingVisual>
                    Published campaign
                  </ActionList.Item>
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
          ) : (
            <Tooltip text="You have no filters defined">
              <Button type="button" variant="primary" trailingAction={TriangleDownIcon} inactive>
                Save as
              </Button>
            </Tooltip>
          )}
        </PageHeader.Actions>
      </PageHeader>
      <hr />
      <div className="mt-2">
        <OrgAlertsFilter
          providers={filterProviders}
          query={query}
          setQuery={onQueryChange}
          advancedFilterDialogRef={advancedFilterDialogRef}
        />
      </div>

      {showIncompleteDataWarning && <LimitedRepoWarning href={incompleteDataWarningDocHref} />}

      <div className="mt-2">
        {query.trim() === '' ? (
          <NewCampaignNoFiltersBlankslate onAddFiltersClick={onAddFiltersClick} />
        ) : (
          <OrgDraftSecurityCampaignAlerts
            query={query}
            group={group}
            organizationLogin={organizationLogin}
            cursor={cursor}
            onCursorChange={onCursorChange}
            onGroupChange={onGroupChange}
            onStateFilterChange={onStateFilterChange}
          />
        )}
      </div>
    </>
  )
}
