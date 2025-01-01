import {ActionList, ActionMenu, PageHeader, Button, Tooltip} from '@primer/react'
import {useMemo, useState, useCallback, useRef} from 'react'
import {GoalIcon, IssueDraftIcon, TriangleDownIcon} from '@primer/octicons-react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {OrgAlertsFilter} from '../components/OrgAlertsFilter'
import {LimitedRepoWarning} from '../components/LimitedRepoWarning'
import {useAlertsParams} from '../hooks/use-alerts-params'
import {useAlertFilterProviders} from '../hooks/use-alert-filter-providers'
import {
  codeScanningOrgAlertListPath,
  securityCampaignOrgCampaignPath,
  securityCampaignOrgCampaignPublishPath,
  securityCampaignOrgCampaignsPath,
} from '@github-ui/paths'
import {useCreateDraftSecurityCampaignMutation} from '../hooks/use-create-draft-security-campaign-mutation'
import {useNavigate} from '@github-ui/use-navigate'
import {OrgDraftSecurityCampaignAlerts} from '../components/OrgDraftSecurityCampaignAlerts'
import {OrgSecurityCampaignBreadcrumbs} from '../components/OrgSecurityCampaignBreadcrumbs'
import {NewCampaignNoFiltersBlankslate} from '../components/NewCampaignNoFiltersBlankslate'
import {UpsertDraftSecurityCampaignFormDialog} from '../components/UpsertDraftSecurityCampaignFormDialog'
import type {AdvancedFilterDialogRef} from '@github-ui/filter'
import {AlertsLimitReachedDialog} from '../components/AlertsLimitReachedDialog'
import {useOrgAlertsQuery} from '../hooks/use-org-alerts-query'
import type {SecurityCampaignForm} from '../types/security-campaign'
import type {User} from '../types/user'

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
  showLimitedAlertsWarning: boolean
  campaignName: string | null
  campaignDescription: string | null
  maxAlerts: number
  bestPracticeCampaignsDocsUrl: string
  hasOpenSpam: boolean
  hasDraftSpam: boolean
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
    showLimitedAlertsWarning,
    campaignName,
    campaignDescription,
    maxAlerts,
    bestPracticeCampaignsDocsUrl,
    hasOpenSpam,
    hasDraftSpam,
  } = useRoutePayload<OrgSecurityCampaignNewPayload>()
  const maxDraftCampaignsReached = orgDraftCampaignsCount >= maxDraftCampaigns
  const maxOpenCampaignsReached = orgOpenCampaignsCount >= maxOpenCampaigns

  const navigate = useNavigate()

  const [isAlertsLimitReachedDialogOpen, setIsAlertsLimitReachedDialogOpen] = useState(false)

  const [isSaveDialogOpen, setIsSaveDialogOpen] = useState(false)
  const {query, cursor, group, onQueryChange, onCursorChange, onGroupChange, onStateFilterChange} = useAlertsParams({
    initialQuery: '',
    initialGroup: 'none',
  })

  const filterProviders = useAlertFilterProviders({
    organizationLogin,
    showSort: false,
    showNewAutofixFilters,
    showCampaignFilter: true,
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
  const savePublishedCampaignDisabled = maxOpenCampaignsReached || isLoading

  const {data} = useOrgAlertsQuery(
    codeScanningOrgAlertListPath({org: organizationLogin}),
    {query, cursor: null},
    isValid && !isLoading && !savePublishedCampaignDisabled,
  )
  const allAlertsCount = data?.alertCount || 0
  const alertsLimitReached = allAlertsCount > maxAlerts

  const navigateToPublishCampaign = () => {
    navigate(
      securityCampaignOrgCampaignPublishPath({
        org: organizationLogin,
        query,
        campaignName: campaignName || undefined,
        campaignDescription: campaignDescription || undefined,
      }),
    )
  }
  const onSavePublishedCampaign = () => {
    if (alertsLimitReached) {
      setIsAlertsLimitReachedDialogOpen(true)
    } else {
      navigateToPublishCampaign()
    }
  }

  const saveAsDisabledTooltipText = useMemo(() => {
    if (!isValid) {
      return `You have no filters defined`
    }
    if (allAlertsCount === 0) {
      return 'Could not find any alerts to include in the campaign'
    }

    return undefined
  }, [isValid, allAlertsCount])

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
      {isAlertsLimitReachedDialogOpen && (
        <AlertsLimitReachedDialog
          setIsOpen={setIsAlertsLimitReachedDialogOpen}
          onProceed={navigateToPublishCampaign}
          maxAlerts={maxAlerts}
          bestPracticeCampaignsDocsUrl={bestPracticeCampaignsDocsUrl}
        />
      )}
      <OrgSecurityCampaignBreadcrumbs
        href={securityCampaignOrgCampaignsPath({org: organizationLogin})}
        text="Campaigns"
        selectedText="Select filters"
      />
      <PageHeader aria-label="Create a new campaign" className="f2 text-normal">
        <PageHeader.TitleArea>
          <PageHeader.Title>Create a new campaign</PageHeader.Title>
        </PageHeader.TitleArea>
        <PageHeader.Actions>
          {saveAsDisabledTooltipText === undefined ? (
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
                        ? `Limit of ${maxDraftCampaigns} draft ${
                            hasDraftSpam ? 'and spam ' : ''
                          }campaigns has been reached`
                        : undefined
                    }
                  >
                    <ActionList.LeadingVisual>
                      <IssueDraftIcon />
                    </ActionList.LeadingVisual>
                    Draft campaign
                  </ActionList.Item>
                  <ActionList.Item
                    onSelect={onSavePublishedCampaign}
                    loading={isLoading}
                    disabled={savePublishedCampaignDisabled}
                    inactiveText={
                      maxOpenCampaignsReached
                        ? `Limit of ${maxOpenCampaigns} open ${
                            hasOpenSpam ? 'and spam ' : ''
                          } campaigns has been reached`
                        : undefined
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
            <Tooltip text={saveAsDisabledTooltipText}>
              <Button type="button" variant="primary" trailingAction={TriangleDownIcon} inactive>
                Save as
              </Button>
            </Tooltip>
          )}
        </PageHeader.Actions>
      </PageHeader>
      <hr className="mt-2 mb-3" />
      <div className="my-3">
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
            showLimitedAlertsWarning={showLimitedAlertsWarning}
          />
        )}
      </div>
    </>
  )
}
