import {Flash, Stack} from '@primer/react'
import type {MutateOptions} from '@github-ui/react-query'
import {OrgProgressMetric} from '../components/OrgProgressMetric'
import {useCallback, useMemo, useState} from 'react'
import {useBannerContext} from '@github-ui/role-assignments/banner-provider'
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
import type {SecurityCampaignForm} from '../types/security-campaign'

export interface OrgPublishedSecurityCampaignPayload {
  payload: OrgSecurityCampaignPayload
}

export function OrgPublishedSecurityCampaign({payload}: OrgPublishedSecurityCampaignPayload) {
  const [campaign, setCampaign] = useState(payload.campaign)
  const closedAt = useMemo(() => (campaign.closedAt ? new Date(campaign.closedAt) : undefined), [campaign.closedAt])

  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)
  const [isDeleteConfirmationDialogOpen, setIsDeleteConfirmationDialogOpen] = useState(false)

  const {sendClickAnalyticsEvent} = useClickAnalytics()
  const {showBanner, navigate} = useBannerContext()

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
          setCampaign(response.campaign)

          if (response.showFlashMessage) {
            if (response.message) {
              showBanner({
                message: response.message,
                variant: 'success',
              })
            }
          } else {
            // Need to do a full page reload so that the campaign name in the sidebar (which is not react) gets updated
            window.location.reload()
          }
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

  const deleteCampaign = async () => {
    mutateDelete(undefined, {
      onSuccess: response => {
        navigate(
          payload.indexPageEnabled
            ? securityCampaignOrgCampaignsPath({
                org: payload.organizationLogin,
                state: campaign.closedAt ? 'closed' : 'open',
              })
            : securityOverviewPath({org: payload.organizationLogin}),
          {
            reloadDocument: !response.showFlashMessage,
          },
          response.showFlashMessage
            ? {
                message: `The campaign ${campaign.name} was successfully deleted.`,
                variant: 'success',
              }
            : undefined,
        )
      },
      onError: () => {
        setIsDeleteConfirmationDialogOpen(false)
      },
    })
  }

  const closeCampaign = async () => {
    mutateClose(undefined, {
      onSuccess: response => {
        if (response.showFlashMessage) {
          setCampaign(response.campaign)
          showBanner({
            message: 'The campaign was successfully closed.',
            variant: 'success',
          })
        } else {
          // window.location.reload is used instead of invalidating the query as invalidating the query does not show
          // the flash message
          window.location.reload()
        }
      },
    })
  }

  const reopenCampaign = async () => {
    mutateReopen(undefined, {
      onSuccess: response => {
        if (response.showFlashMessage) {
          setCampaign(response.campaign)
          showBanner({
            message: 'The campaign was successfully reopened.',
            variant: 'success',
          })
        } else {
          // window.location.reload is used instead of invalidating the query as invalidating the query does not show
          // the flash message
          window.location.reload()
        }
      },
    })
  }

  const duplicateCampaign = () => {
    sendCreateAnalyticsEvent()
    navigate(
      securityCampaignsOrgNewCampaignPath({
        org: payload.organizationLogin,
        query: payload.campaign.creationQuery ?? undefined,
        sourceCampaignNumber: campaign.number,
      }),
    )
  }

  const filterProviders = useAlertFilterProviders({
    organizationLogin: payload.organizationLogin,
    showSort: true,
    showNewAutofixFilters: payload.showNewAutofixFilters,
    showCampaignFilter: false, // Never show the campaign filter within a campaign
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
          readOnly={!!closedAt}
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
          isDraft={false}
        />
        <Stack direction="horizontal" align="center" gap="condensed">
          <CampaignFeedbackLink />
          {payload.showCampaignManagementActions && (
            <CampaignActionMenu
              onEditCampaignClicked={() => setIsEditDialogOpen(true)}
              onDeleteCampaignClicked={() => setIsDeleteConfirmationDialogOpen(true)}
              onCloseCampaignClicked={closeCampaign}
              onReopenCampaignClicked={reopenCampaign}
              onDuplicateCampaignClicked={duplicateCampaign}
              isClosed={!!closedAt}
              isQueryEmpty={!payload.campaign.creationQuery}
            />
          )}
        </Stack>
      </Stack>
      <p className="color-fg-muted mb-3">{campaign.description}</p>
      <Stack direction="horizontal" gap="condensed" wrap="wrap">
        <OrgProgressMetric
          alertsPath={alertsPath}
          endsAt={new Date(campaign.endsAt)}
          createdAt={new Date(campaign.createdAt)}
          isClosed={!!closedAt}
        />
        <OrgStatusMetric endsAt={new Date(campaign.endsAt)} alertsPath={alertsPath} closedAt={closedAt} />
        <OrgAutofixSupportedMetric alertsPath={alertsPath} />
      </Stack>
      <div className="flex-1">
        <div className="flex-1 mt-3">
          <OrgAlertsFilter providers={filterProviders} query={query} setQuery={onQueryChange} />
          {showRevert && (
            <div className="mt-2">
              <FilterRevert as="button" onClick={revertQuery} />
            </div>
          )}
        </div>
      </div>
      {payload.showIncompleteDataWarning && <LimitedRepoWarning href={payload.incompleteDataWarningDocHref} />}
      <div className="mt-3">
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
          showLimitedAlertsWarning={payload.showLimitedAlertsWarning}
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
      </div>
    </>
  )
}
