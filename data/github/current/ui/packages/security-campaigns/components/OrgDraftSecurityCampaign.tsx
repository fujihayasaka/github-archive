import {useAlertFilterProviders} from '../hooks/use-alert-filter-providers'
import {ActionList, ActionMenu, Button, Flash, IconButton, Stack, sx, Tooltip} from '@primer/react'
import {
  securityCampaignOrgCampaignsPath,
  securityCampaignOrgDeleteDraftPath,
  codeScanningOrgAlertListPath,
  securityCampaignOrgDraftCampaignPublishPath,
} from '@github-ui/paths'
import {useAlertsParams} from '../hooks/use-alerts-params'
import {LimitedRepoWarning} from './LimitedRepoWarning'
import type {OrgSecurityCampaignPayload} from '../types/org-security-campaign-payload'
import {OrgSecurityCampaignBreadcrumbs} from './OrgSecurityCampaignBreadcrumbs'
import {useCallback, useMemo, useState} from 'react'
import {OrgDraftSecurityCampaignAlerts} from './OrgDraftSecurityCampaignAlerts'
import {OrgDraftProgressMetric} from './OrgDraftProgressMetric'
import DataCard from '@github-ui/data-card'
import {useDeleteSecurityCampaignMutation} from '../hooks/use-delete-security-campaign-mutation'
import {KebabHorizontalIcon, PencilIcon, TrashIcon} from '@primer/octicons-react'
import {DeleteCampaignConfirmationDialog} from './DeleteCampaignConfirmationDialog'
import {OrgDraftAutofixSupportedMetric} from './OrgDraftAutofixSupportedMetric'
import {UpsertDraftSecurityCampaignFormDialog} from './UpsertDraftSecurityCampaignFormDialog'
import {useEditDraftSecurityCampaignMutation} from '../hooks/use-edit-draft-security-campaign-mutation'
import {OrgDraftAlertsFilter} from './OrgDraftAlertsFilter'
import {OrgSecurityCampaignHeading} from './OrgSecurityCampaignHeading'
import {CampaignFeedbackLink} from './CampaignFeedbackLink'
import {useOrgAlertsQuery} from '../hooks/use-org-alerts-query'
import {useBannerContext} from '@github-ui/role-assignments/banner-provider'
import {useSyncedState} from '@github-ui/use-synced-state'
import {AlertsLimitReachedDialog} from './AlertsLimitReachedDialog'
import type {SecurityCampaignForm} from '../types/security-campaign'

export interface OrgDraftSecurityCampaignProps {
  payload: OrgSecurityCampaignPayload
}

export function OrgDraftSecurityCampaign({payload}: OrgDraftSecurityCampaignProps) {
  const {
    organizationLogin,
    currentUser,
    customPropertyNames,
    maxManagers,
    showNewAutofixFilters,
    showCampaignManagementActions,
    showIncompleteDataWarning,
    incompleteDataWarningDocHref,
    showLimitedAlertsWarning,
    openOrgCampaignsCount,
    maxCampaigns,
    maxAlerts,
    bestPracticeCampaignsDocsUrl,
    hasOpenSpam,
  } = payload

  const [campaign, setCampaign] = useState(payload.campaign)
  const campaignsLimitReached = (openOrgCampaignsCount ?? 0) >= maxCampaigns

  // Draft campaigns should always have a creation query but setting a default
  // value to satisfy the type checker
  const [query, setQuery] = useState(campaign.creationQuery || 'is:open')
  const [filterValue, setFilterValue] = useSyncedState(query)
  const isFilterChangeUnsaved = filterValue !== campaign.creationQuery

  const filterProviders = useAlertFilterProviders({
    organizationLogin,
    showSort: false,
    showNewAutofixFilters,
    showCampaignFilter: true,
    customPropertyNames,
  })

  const {cursor, group, onCursorChange, onGroupChange, onStateFilterChange} = useAlertsParams({
    initialGroup: 'none',
  })

  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)
  const [isAlertsLimitReachedDialogOpen, setIsAlertsLimitReachedDialogOpen] = useState(false)

  const alertsPath = codeScanningOrgAlertListPath({org: organizationLogin})
  const {data, isLoading: isAlertQueryLoading} = useOrgAlertsQuery(alertsPath, {query, cursor: null}, query !== '')
  const allAlertsCount = data?.alertCount || 0
  const alertsLimitReached = allAlertsCount > maxAlerts

  const {
    mutate: mutateEdit,
    isPending: isEditPending,
    error: editError,
    reset,
  } = useEditDraftSecurityCampaignMutation(organizationLogin, campaign.number)

  const editCampaign = useCallback(
    (updatedCampaign: SecurityCampaignForm) => {
      mutateEdit(
        {
          campaignName: updatedCampaign.name,
          campaignDescription: updatedCampaign.description,
          query,
          campaignManagers: updatedCampaign.managers.map(user => user.id),
          campaignTeamManagers: updatedCampaign.teamManagers.map(team => team.id),
          campaignContactLink: updatedCampaign.contactLink,
        },
        {
          onSuccess: response => {
            setCampaign(response.campaign)
            setIsEditDialogOpen(false)
          },
        },
      )
    },
    [mutateEdit, query],
  )
  const [isDeleteConfirmationDialogOpen, setIsDeleteConfirmationDialogOpen] = useState(false)

  const {
    mutate: mutateDelete,
    error: deleteError,
    isPending: isDeletePending,
    isSuccess: isDeleteSuccess,
  } = useDeleteSecurityCampaignMutation(
    securityCampaignOrgDeleteDraftPath({org: organizationLogin, securityCampaignNumber: campaign.number}),
  )

  const {navigate} = useBannerContext()
  const deleteCampaign = async () => {
    mutateDelete(undefined, {
      onSuccess: () => {
        navigate(
          securityCampaignOrgCampaignsPath({org: organizationLogin, state: 'draft'}),
          {},
          {
            message: `The campaign ${campaign.name} was successfully deleted.`,
            variant: 'success',
          },
        )
      },
      onError: () => {
        setIsDeleteConfirmationDialogOpen(false)
      },
    })
  }

  const handleStateFilterChange = (state: 'open' | 'closed') => {
    onStateFilterChange(state)

    const queryWithoutState = query.replaceAll(/is:(open|closed)/g, '').trim()
    setQuery(`is:${state} ${queryWithoutState}`.trim())
  }

  const reviewAndPublishTooltipText = useMemo(() => {
    if (campaignsLimitReached) {
      return `Limit of ${maxCampaigns} open ${hasOpenSpam ? 'and spam ' : ''}campaigns is reached`
    }
    if (isFilterChangeUnsaved) {
      return 'Filter query has changed. Please discard or save the changes before publishing'
    }
    if (allAlertsCount === 0) {
      return 'Could not find any alerts to include in the campaign'
    }

    return undefined
  }, [campaignsLimitReached, isFilterChangeUnsaved, allAlertsCount, maxCampaigns, hasOpenSpam])

  const navigateToPublishCampaign = () => {
    navigate(
      securityCampaignOrgDraftCampaignPublishPath({
        org: organizationLogin,
        securityCampaignNumber: campaign.number,
      }),
    )
  }

  const reviewAndPublishButtonInactive = isFilterChangeUnsaved || campaignsLimitReached || allAlertsCount === 0

  const onReviewAndPublishClick = async () => {
    if (reviewAndPublishButtonInactive) return

    if (alertsLimitReached) {
      setIsAlertsLimitReachedDialogOpen(true)
    } else {
      navigateToPublishCampaign()
    }
  }

  const reviewAndPublishButton = (
    <Button onClick={onReviewAndPublishClick} size="medium" inactive={reviewAndPublishButtonInactive} variant="primary">
      Review and publish campaign
    </Button>
  )

  return (
    <>
      {isAlertsLimitReachedDialogOpen && (
        <AlertsLimitReachedDialog
          setIsOpen={setIsAlertsLimitReachedDialogOpen}
          onProceed={navigateToPublishCampaign}
          maxAlerts={maxAlerts}
          bestPracticeCampaignsDocsUrl={bestPracticeCampaignsDocsUrl}
        />
      )}
      {isDeleteConfirmationDialogOpen && (
        <DeleteCampaignConfirmationDialog
          setIsOpen={setIsDeleteConfirmationDialogOpen}
          deleteCampaign={deleteCampaign}
          disabled={isDeletePending || isDeleteSuccess}
          isDraft={!campaign.publishedAt}
          campaignName={campaign.name}
        />
      )}
      {deleteError && (
        <Flash variant="danger" sx={{mb: 2}}>
          {deleteError.message}
        </Flash>
      )}
      {isEditDialogOpen && (
        <UpsertDraftSecurityCampaignFormDialog
          organizationLogin={organizationLogin}
          currentUser={currentUser}
          setIsOpen={setIsEditDialogOpen}
          submitForm={editCampaign}
          isPending={isEditPending}
          formError={editError}
          resetForm={reset}
          maxManagers={maxManagers}
          campaign={campaign}
        />
      )}
      <OrgSecurityCampaignBreadcrumbs
        href={securityCampaignOrgCampaignsPath({org: organizationLogin})}
        text="Campaigns"
        selectedText={campaign.name}
      />
      <Stack
        direction="horizontal"
        align="start"
        justify="space-between"
        gap="normal"
        className="border-bottom pb-2 mb-2"
      >
        <OrgSecurityCampaignHeading
          campaignName={campaign.name}
          userManagers={campaign.managers}
          teamManagers={campaign.teamManagers}
          contactLink={campaign.contactLink}
          isDraft
        />
        <Stack direction="horizontal" align="center" gap="condensed">
          <CampaignFeedbackLink />
          {showCampaignManagementActions && (
            <>
              {!isAlertQueryLoading && reviewAndPublishTooltipText ? (
                <Tooltip text={reviewAndPublishTooltipText} direction="n">
                  {reviewAndPublishButton}
                </Tooltip>
              ) : (
                reviewAndPublishButton
              )}
              <ActionMenu>
                <ActionMenu.Anchor>
                  <IconButton icon={KebabHorizontalIcon} aria-label="Campaign options" sx={sx} />
                </ActionMenu.Anchor>
                <ActionMenu.Overlay>
                  <ActionList>
                    <ActionList.Item onSelect={() => setIsEditDialogOpen(true)}>
                      <PencilIcon /> Edit draft
                    </ActionList.Item>
                    <ActionList.Item variant="danger" onSelect={() => setIsDeleteConfirmationDialogOpen(true)}>
                      <TrashIcon /> Delete draft
                    </ActionList.Item>
                  </ActionList>
                </ActionMenu.Overlay>
              </ActionMenu>
            </>
          )}
        </Stack>
      </Stack>
      <p className="fgColor-muted mb-3">{campaign.description}</p>
      <Stack direction="horizontal" gap="condensed" wrap="wrap" data-testid="org-draft-security-campaign-metrics">
        <OrgDraftProgressMetric alertsCount={allAlertsCount} maxAlerts={maxAlerts} />
        <DataCard cardTitle="Status" sx={{color: 'fg.muted'}}>
          <div>
            <div className="f2 lh-condensed-ultra text-normal">Draft</div>
          </div>
          <DataCard.Description>
            <>The campaign is not published yet.</>
          </DataCard.Description>
        </DataCard>
        <OrgDraftAutofixSupportedMetric alertsPath={alertsPath} query={query} isDraft />
      </Stack>
      <OrgDraftAlertsFilter
        providers={filterProviders}
        filterValue={filterValue}
        setFilterValue={setFilterValue}
        setQuery={(newQuery: string) => {
          setQuery(newQuery)
          onCursorChange(null)
        }}
        campaign={campaign}
        setCampaign={setCampaign}
        organizationLogin={organizationLogin}
      />
      {showIncompleteDataWarning && <LimitedRepoWarning href={incompleteDataWarningDocHref} />}
      <OrgDraftSecurityCampaignAlerts
        query={query}
        group={group}
        organizationLogin={organizationLogin}
        cursor={cursor}
        onCursorChange={onCursorChange}
        onGroupChange={onGroupChange}
        onStateFilterChange={handleStateFilterChange}
        showLimitedAlertsWarning={showLimitedAlertsWarning}
      />
    </>
  )
}
