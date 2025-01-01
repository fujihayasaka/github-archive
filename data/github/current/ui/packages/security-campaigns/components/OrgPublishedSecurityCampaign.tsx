import type {SecurityCampaignForm} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {Box, Flash, Text} from '@primer/react'
import type {MutateOptions} from '@github-ui/react-query'
import {OrgProgressMetric} from '../components/OrgProgressMetric'
import {useCallback, useMemo, useState} from 'react'
import {useNavigate} from '@github-ui/use-navigate'
import {CampaignActionMenu} from '../components/CampaignActionMenu'
import {
  useUpdateSecurityCampaignMutation,
  type UpdateSecurityCampaignRequest,
  type UpdateSecurityCampaignResponse,
} from '../hooks/use-update-security-campaign-mutation'
import {useDeleteSecurityCampaignMutation} from '../hooks/use-delete-security-campaign-mutation'
import {OrgAlertsFilter} from './OrgAlertsFilter'
import {FilterRevert} from '@github-ui/filter'
import {EditSecurityCampaignFormDialog} from './EditSecurityCampaignFormDialog'
import {DeleteCampaignConfirmationDialog} from './DeleteCampaignConfirmationDialog'
import {useCloseSecurityCampaignMutation} from '../hooks/use-close-security-campaign-mutation'
import {OrgStatusMetric} from './OrgStatusMetric'
import {useReopenSecurityCampaignMutation} from '../hooks/use-reopen-security-campaign-mutation'
import {OrgAutofixSupportedMetric} from './OrgAutofixSupportedMetric'
import {useAlertsParams} from '../hooks/use-alerts-params'
import {LimitedRepoWarning} from './LimitedRepoWarning'
import {useClickAnalytics} from '@github-ui/use-analytics'
import {
  orgCodeScanningPath,
  securityCampaignOrgAlertsGroupsPath,
  securityCampaignOrgAlertsPath,
  securityCampaignOrgCampaignClosePath,
  securityCampaignOrgCampaignDeletePath,
  securityCampaignOrgCampaignEditPath,
  securityCampaignOrgCampaignReopenPath,
  securityCampaignOrgCampaignsPath,
  securityCampaignOrgClosedPath,
  securityCampaignsOrgNewCampaignPath,
  securityOverviewPath,
} from '@github-ui/paths'
import {useAlertFilterProviders} from '../hooks/use-alert-filter-providers'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {CampaignProgressBar} from './CampaignProgressBar'
import {OrgSecurityCampaignAlerts} from './OrgSecurityCampaignAlerts'
import type {OrgSecurityCampaignPayload} from '../types/org-security-campaign-payload'
import {OrgSecurityCampaignBreadcrumbs} from './OrgSecurityCampaignBreadcrumbs'
import {OrgSecurityCampaignHeading} from './OrgSecurityCampaignHeading'
import {CampaignFeedbackLink} from './CampaignFeedbackLink'

export interface OrgPublishedSecurityCampaignPayload {
  payload: OrgSecurityCampaignPayload
}

export function OrgPublishedSecurityCampaign({payload}: OrgPublishedSecurityCampaignPayload) {
  const [campaign, setCampaign] = useState(payload.campaign)
  const closedAt = useMemo(() => (campaign.closedAt ? new Date(campaign.closedAt) : undefined), [campaign.closedAt])

  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)
  const [isDeleteConfirmationDialogOpen, setIsDeleteConfirmationDialogOpen] = useState(false)

  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const {
    mutate: mutateEdit,
    isPending: isEditPending,
    error: editError,
    reset,
  } = useUpdateSecurityCampaignMutation(
    securityCampaignOrgCampaignEditPath({org: payload.organizationLogin, securityCampaignNumber: campaign.number}),
  )
  const {
    mutate: mutateDelete,
    error: deleteError,
    isPending: isDeletePending,
    isSuccess: isDeleteSuccess,
  } = useDeleteSecurityCampaignMutation(
    securityCampaignOrgCampaignDeletePath({
      org: payload.organizationLogin,
      securityCampaignNumber: campaign.number,
    }),
  )

  const {mutate: mutateClose, error: closeError} = useCloseSecurityCampaignMutation(
    securityCampaignOrgCampaignClosePath({
      org: payload.organizationLogin,
      securityCampaignNumber: campaign.number,
    }),
  )
  const {mutate: mutateReopen, error: reopenError} = useReopenSecurityCampaignMutation(
    securityCampaignOrgCampaignReopenPath({
      org: payload.organizationLogin,
      securityCampaignNumber: campaign.number,
    }),
  )
  const editCampaign = async (
    updatedCampaign: SecurityCampaignForm,
    {onSuccess, ...options}: MutateOptions<UpdateSecurityCampaignResponse, Error, UpdateSecurityCampaignRequest>,
  ) => {
    mutateEdit(
      {
        campaignName: updatedCampaign.name,
        campaignDescription: updatedCampaign.description,
        campaignDueDate: updatedCampaign.endsAt,
        campaignManagers: updatedCampaign.managers.map(manager => manager.id),
        campaignContactLink: updatedCampaign.contactLink,
        campaignTeamManagers: updatedCampaign.teamManagers.map(team => team.id),
      },
      {
        ...options,
        onSuccess: (response, variables, context) => {
          onSuccess?.(response, variables, context)
          setCampaign(oldCampaign => ({...oldCampaign, ...updatedCampaign}))

          // Need to do a full page reload so that the campaign name in the sidebar (which is not react) gets updated
          window.location.reload()
        },
      },
    )
  }

  const sendCreateAnalyticsEvent = useCallback(() => {
    sendClickAnalyticsEvent({
      category: 'security_campaigns',
      action: 'duplicate',
      label: `source_campaign_id:${campaign.id};org_id:${payload.orgId}`,
    })
  }, [campaign.id, payload.orgId, sendClickAnalyticsEvent])

  const navigate = useNavigate()
  const deleteCampaign = async () => {
    mutateDelete(undefined, {
      onSuccess: () => {
        navigate(
          payload.indexPageEnabled
            ? securityCampaignOrgCampaignsPath({
                org: payload.organizationLogin,
                state: campaign.closedAt ? 'closed' : 'open',
              })
            : securityOverviewPath({org: payload.organizationLogin}),
        )
      },
      onError: () => {
        setIsDeleteConfirmationDialogOpen(false)
      },
    })
  }

  const closeCampaign = async () => {
    mutateClose(undefined, {
      onSuccess: () => {
        // window.location.reload is used instead of invalidating the query as invalidating the query does not show
        // the flash message
        window.location.reload()
      },
    })
  }

  const reopenCampaign = async () => {
    mutateReopen(undefined, {
      onSuccess: () => {
        // window.location.reload is used instead of invalidating the query as invalidating the query does not show
        // the flash message
        window.location.reload()
      },
    })
  }

  const duplicateCampaign = () => {
    sendCreateAnalyticsEvent()
    if (payload.draftCampaignsEnabled) {
      navigate(
        securityCampaignsOrgNewCampaignPath({
          org: payload.organizationLogin,
          query: payload.campaign.creationQuery ?? undefined,
          sourceCampaignNumber: campaign.number,
        }),
      )
    } else {
      navigate(
        orgCodeScanningPath({
          org: payload.organizationLogin,
          query: payload.campaign.creationQuery ?? undefined,
          sourceCampaignNumber: payload.campaign.number,
        }),
      )
    }
  }

  const filterProviders = useAlertFilterProviders({
    organizationLogin: payload.organizationLogin,
    showNewAutofixFilters: payload.showNewAutofixFilters,
    customPropertyNames: payload.customPropertyNames,
    securityCampaignNumber: payload.campaign.number,
  })

  const {
    query,
    cursor,
    group,
    onQueryChange,
    onCursorChange,
    onGroupChange,
    onStateFilterChange,
    showRevert,
    revertQuery,
  } = useAlertsParams()

  const showBreadcrumb = payload.indexPageEnabled || !!closedAt
  const breadcrumbText = payload.indexPageEnabled ? 'Campaigns' : 'Closed campaigns'
  const breadcrumbPath = payload.indexPageEnabled
    ? securityCampaignOrgCampaignsPath({org: payload.organizationLogin})
    : securityCampaignOrgClosedPath({org: payload.organizationLogin})

  const alertsPath = securityCampaignOrgAlertsPath({
    org: payload.organizationLogin,
    securityCampaignNumber: payload.campaign.number,
  })

  return (
    <>
      {isEditDialogOpen && (
        <EditSecurityCampaignFormDialog
          organizationLogin={payload.organizationLogin}
          securityCampaignNumber={payload.campaign.number}
          setIsOpen={setIsEditDialogOpen}
          campaign={campaign}
          submitForm={editCampaign}
          isPending={isEditPending}
          formError={editError}
          resetForm={reset}
          maxManagers={payload.maxManagers}
          campaignsGAEnabled={payload.campaignsGAEnabled}
          readOnly={payload.campaignsGAEnabled && !!closedAt}
        />
      )}
      {isDeleteConfirmationDialogOpen && (
        <DeleteCampaignConfirmationDialog
          setIsOpen={setIsDeleteConfirmationDialogOpen}
          deleteCampaign={deleteCampaign}
          disabled={isDeletePending || isDeleteSuccess}
          campaignName={campaign.name}
          isDraft={false}
        />
      )}
      {deleteError && (
        <Flash variant="danger" sx={{mb: 2}}>
          {deleteError.message}
        </Flash>
      )}
      {closeError && (
        <Flash variant="danger" sx={{mb: 2}}>
          {closeError.message}
        </Flash>
      )}
      {reopenError && (
        <Flash variant="danger" sx={{mb: 2}}>
          {reopenError.message}
        </Flash>
      )}
      {showBreadcrumb && (
        <OrgSecurityCampaignBreadcrumbs href={breadcrumbPath} text={breadcrumbText} selectedText={campaign.name} />
      )}

      <Box
        sx={{display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 2}}
        className="border-bottom pb-2 mb-2"
      >
        <OrgSecurityCampaignHeading
          campaignName={campaign.name}
          userManagers={campaign.managers}
          teamManagers={campaign.teamManagers}
          contactLink={payload.campaign.contactLink}
          isDraft={false}
        />
        <Box sx={{display: 'flex', alignItems: 'center', gap: 2}}>
          {payload.campaignsGAEnabled ? (
            <CampaignFeedbackLink />
          ) : (
            <BetaLabel feedbackUrl="https://gh.io/security-campaigns-feedback" />
          )}
          {payload.showCampaignManagementActions && (
            <CampaignActionMenu
              onEditCampaignClicked={() => setIsEditDialogOpen(true)}
              onDeleteCampaignClicked={() => setIsDeleteConfirmationDialogOpen(true)}
              onCloseCampaignClicked={closeCampaign}
              onReopenCampaignClicked={reopenCampaign}
              onDuplicateCampaignClicked={duplicateCampaign}
              isClosed={!!closedAt}
              campaignsGAEnabled={payload.campaignsGAEnabled}
              isQueryEmpty={!payload.campaign.creationQuery}
            />
          )}
        </Box>
      </Box>
      <Text as="p" sx={{color: 'fg.muted'}}>
        {campaign.description}
      </Text>
      <Box sx={{display: 'flex', gap: 2, flexWrap: 'wrap'}}>
        <OrgProgressMetric
          alertsPath={alertsPath}
          endsAt={new Date(campaign.endsAt)}
          createdAt={new Date(campaign.createdAt)}
          isClosed={!!closedAt}
        />
        <OrgStatusMetric endsAt={new Date(campaign.endsAt)} alertsPath={alertsPath} closedAt={closedAt} />
        <OrgAutofixSupportedMetric alertsPath={alertsPath} />
      </Box>
      <Box sx={{flexGrow: 1}}>
        <Box sx={{flexGrow: 1, mt: 2}}>
          <OrgAlertsFilter providers={filterProviders} query={query} setQuery={onQueryChange} />
          {showRevert && (
            <Box sx={{mt: 1}}>
              <FilterRevert as="button" onClick={revertQuery} />
            </Box>
          )}
        </Box>
      </Box>
      {payload.showIncompleteDataWarning && <LimitedRepoWarning href={payload.incompleteDataWarningDocHref} />}
      <Box sx={{mt: 2}}>
        <OrgSecurityCampaignAlerts
          group={group}
          onGroupChange={onGroupChange}
          alertsPath={alertsPath}
          alertsGroupsPath={securityCampaignOrgAlertsGroupsPath({
            org: payload.organizationLogin,
            securityCampaignNumber: payload.campaign.number,
          })}
          query={query}
          onStateFilterChange={onStateFilterChange}
          cursor={cursor}
          setCursor={onCursorChange}
          alertParentLink={
            closedAt ? {kind: 'repository'} : {kind: 'campaign', campaignNumber: payload.campaign.number}
          }
          renderGroupMetadata={alertGroup => (
            <ListItemMetadata>
              <CampaignProgressBar
                openCount={alertGroup.openCount}
                closedCount={alertGroup.closedCount}
                openWithLinksCount={alertGroup.openWithLinksCount}
              />
            </ListItemMetadata>
          )}
        />
      </Box>
    </>
  )
}
