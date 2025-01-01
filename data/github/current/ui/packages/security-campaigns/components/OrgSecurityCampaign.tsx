import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {SecurityCampaign, SecurityCampaignForm} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {Box, Breadcrumbs, Flash, Heading, Text} from '@primer/react'
import type {MutateOptions} from '@tanstack/react-query'
import {OrgProgressMetric} from '../components/OrgProgressMetric'
import {CampaignManagerText} from './CampaignManagerText'
import {useMemo, useState} from 'react'
import {useNavigate} from '@github-ui/use-navigate'
import {CampaignActionMenu} from '../components/CampaignActionMenu'
import {OrgAlertsList, type OrgAlertsListProps} from '../components/OrgAlertsList'
import {
  useUpdateSecurityCampaignMutation,
  type UpdateSecurityCampaignRequest,
  type UpdateSecurityCampaignResponse,
} from '../hooks/use-update-security-campaign-mutation'
import {useDeleteSecurityCampaignMutation} from '../hooks/use-delete-security-campaign-mutation'
import {
  AutofixFilterProvider,
  ResolutionFilterProvider,
  SeverityFilterProvider,
  SortFilterProvider,
  StateFilterProvider,
} from '../filter-providers/StaticProviders'
import {
  RuleFilterProvider,
  RepositoryFilterProvider,
  TeamFilterProvider,
  TopicFilterProvider,
  ToolFilterProvider,
  TagFilterProvider,
} from '../filter-providers/DynamicProviders'
import {OrgAlertsFilter} from './OrgAlertsFilter'
import {defaultQuery} from './AlertsList'
import {FilterRevert} from '@github-ui/filter'
import {EditSecurityCampaignFormDialog} from './EditSecurityCampaignFormDialog'
import {DeleteCampaignConfirmationDialog} from './DeleteCampaignConfirmationDialog'
import type {AlertsGroup} from '../types/get-alerts-groups-request'
import {AlertsGroupsMenu} from './AlertsGroupsMenu'
import {OrgAlertsGroups} from './OrgAlertsGroups'
import {useCloseSecurityCampaignMutation} from '../hooks/use-close-security-campaign-mutation'
import {OrgStatusMetric} from './OrgStatusMetric'
import {useReopenSecurityCampaignMutation} from '../hooks/use-reopen-security-campaign-mutation'
import {OrgAutofixMetric} from './OrgAutofixMetric'
import {useAlertsParams} from '../hooks/use-alerts-params'
import {BetaFeedback} from './BetaFeedback'
import {isFeatureEnabled} from '@github-ui/feature-flags'

export interface OrgSecurityCampaignPayload {
  campaign: SecurityCampaign
  alertsPath: string
  alertsGroupsPath: string
  campaignManagersPath: string
  securityOverviewPath: string
  orgLevelView: boolean
  suggestionsPath: string
  codeScanningRepoListPath: string
  codeScanningToolListPath: string
  codeScanningRuleListPath: string
  codeScanningTagListPath: string
  closedCampaignsPath: string
  showAutofixGeneratedFilter: boolean
  showCampaignManagementActions: boolean
}

function OrgSecurityCampaignAlerts({
  group,
  onGroupChange,
  ...props
}: OrgAlertsListProps & {
  group: AlertsGroup
  onGroupChange: (group: AlertsGroup) => void
}) {
  const actions = useMemo(
    () => [{key: 'group-by', render: () => <AlertsGroupsMenu group={group} setGroup={onGroupChange} />}],
    [group, onGroupChange],
  )

  if (group === 'none') {
    return <OrgAlertsList {...props} actions={actions} />
  }

  return <OrgAlertsGroups {...props} group={group} actions={actions} />
}

export function OrgSecurityCampaign() {
  const payload = useRoutePayload<OrgSecurityCampaignPayload>()

  const [campaign, setCampaign] = useState(payload.campaign)
  const closedAt = useMemo(() => (campaign.closedAt ? new Date(campaign.closedAt) : undefined), [campaign.closedAt])

  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)
  const [isDeleteConfirmationDialogOpen, setIsDeleteConfirmationDialogOpen] = useState(false)

  const {
    mutate: mutateEdit,
    isPending: isEditPending,
    error: editError,
    reset,
  } = useUpdateSecurityCampaignMutation(payload.campaign.updatePath)
  const {
    mutate: mutateDelete,
    error: deleteError,
    isPending: isDeletePending,
    isSuccess: isDeleteSuccess,
  } = useDeleteSecurityCampaignMutation(payload.campaign.deletePath)

  const {mutate: mutateClose, error: closeError} = useCloseSecurityCampaignMutation(payload.campaign.closePath)
  const {mutate: mutateReopen, error: reopenError} = useReopenSecurityCampaignMutation(payload.campaign.reopenPath)
  const editCampaign = async (
    updatedCampaign: SecurityCampaignForm,
    {onSuccess, ...options}: MutateOptions<UpdateSecurityCampaignResponse, Error, UpdateSecurityCampaignRequest>,
  ) => {
    mutateEdit(
      {
        campaignName: updatedCampaign.name,
        campaignDescription: updatedCampaign.description,
        campaignDueDate: updatedCampaign.endsAt,
        campaignManager: updatedCampaign.manager?.id ?? 0,
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

  const navigate = useNavigate()
  const deleteCampaign = async () => {
    mutateDelete(undefined, {
      onSuccess: () => {
        navigate(payload.securityOverviewPath)
      },
      onError: () => {
        setIsDeleteConfirmationDialogOpen(false)
      },
    })
  }

  const closeCampaign = async () => {
    mutateClose(undefined, {
      onSuccess: response => {
        window.location.href = response.redirect // This is used instead of navigate as navigate does not show the flash message
      },
    })
  }

  const reopenCampaign = async () => {
    mutateReopen(undefined, {
      onSuccess: response => {
        window.location.href = response.redirect // This is used instead of navigate as navigate does not show the flash message
      },
    })
  }

  // Order determins the position of the filter in suggestion list.
  const filterProviders = useMemo(
    () => [
      new RepositoryFilterProvider({
        path: payload.codeScanningRepoListPath,
        securityCampaignNumber: payload.campaign.number,
      }),
      new ResolutionFilterProvider(),
      new RuleFilterProvider({path: payload.codeScanningRuleListPath, securityCampaignNumber: payload.campaign.number}),
      new TagFilterProvider({path: payload.codeScanningTagListPath, securityCampaignNumber: payload.campaign.number}),
      new SeverityFilterProvider(),
      new SortFilterProvider(),
      new StateFilterProvider(),
      new TeamFilterProvider({path: payload.suggestionsPath}),
      new ToolFilterProvider({path: payload.codeScanningToolListPath, securityCampaignNumber: payload.campaign.number}),
      new TopicFilterProvider({path: payload.suggestionsPath}),
      new AutofixFilterProvider(payload.showAutofixGeneratedFilter),
    ],
    [
      payload.codeScanningRepoListPath,
      payload.campaign.number,
      payload.codeScanningRuleListPath,
      payload.codeScanningTagListPath,
      payload.codeScanningToolListPath,
      payload.suggestionsPath,
      payload.showAutofixGeneratedFilter,
    ],
  )
  const {query, cursor, group, onQueryChange, onCursorChange, onGroupChange} = useAlertsParams()

  const onStateFilterChange = (state: 'open' | 'closed') => {
    const queryWithoutState = query.replaceAll(/is:(open|closed)/g, '').trim()
    onQueryChange(`is:${state} ${queryWithoutState}`)
  }

  const showRevert = query !== defaultQuery
  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')

  return (
    <>
      {isEditDialogOpen && (
        <EditSecurityCampaignFormDialog
          setIsOpen={setIsEditDialogOpen}
          campaign={campaign}
          submitForm={editCampaign}
          isPending={isEditPending}
          formError={editError}
          resetForm={reset}
          campaignManagersPath={payload.campaignManagersPath}
        />
      )}
      {isDeleteConfirmationDialogOpen && (
        <DeleteCampaignConfirmationDialog
          setIsOpen={setIsDeleteConfirmationDialogOpen}
          deleteCampaign={deleteCampaign}
          disabled={isDeletePending || isDeleteSuccess}
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
      {!!closedAt && (
        <Breadcrumbs>
          <Breadcrumbs.Item href={payload.closedCampaignsPath}>Closed campaigns</Breadcrumbs.Item>
          <Breadcrumbs.Item selected>{campaign.name}</Breadcrumbs.Item>
        </Breadcrumbs>
      )}
      <Box sx={{display: 'flex', alignItems: 'center', justifyContent: 'space-between'}}>
        <Box sx={{display: 'flex', flexDirection: 'row', alignItems: 'baseline', gap: 2}}>
          <Heading data-hpc as="h2">
            {campaign.name}
          </Heading>
          <CampaignManagerText manager={campaign.manager} />
        </Box>
        <Box sx={{display: 'flex', alignItems: 'center', gap: 2}}>
          {lifecycleLabelNameEnabled ? (
            <BetaLabel feedbackUrl="https://gh.io/security-campaigns-feedback" />
          ) : (
            <BetaFeedback />
          )}
          {payload.showCampaignManagementActions && (
            <CampaignActionMenu
              onEditCampaignClicked={() => setIsEditDialogOpen(true)}
              onDeleteCampaignClicked={() => setIsDeleteConfirmationDialogOpen(true)}
              onCloseCampaignClicked={closeCampaign}
              onReopenCampaignClicked={reopenCampaign}
              isClosed={!!closedAt}
            />
          )}
        </Box>
      </Box>
      <Text as="p" sx={{color: 'fg.muted'}}>
        {campaign.description}
      </Text>
      <Box sx={{display: 'flex', gap: 2}}>
        <OrgProgressMetric
          alertsPath={payload.alertsPath}
          endsAt={new Date(campaign.endsAt)}
          createdAt={new Date(campaign.createdAt)}
          isClosed={!!closedAt}
        />
        <OrgStatusMetric endsAt={new Date(campaign.endsAt)} alertsPath={payload.alertsPath} closedAt={closedAt} />
        <OrgAutofixMetric alertsPath={payload.alertsPath} />
      </Box>
      <Box sx={{flexGrow: 1}}>
        <Box sx={{flexGrow: 1, mt: 2}}>
          <OrgAlertsFilter providers={filterProviders} query={query} setQuery={onQueryChange} />
          {showRevert && (
            <Box sx={{mt: 1}}>
              <FilterRevert
                as="button"
                onClick={() => {
                  onQueryChange(defaultQuery)
                }}
              />
            </Box>
          )}
        </Box>
      </Box>
      <Box sx={{mt: 2}}>
        <OrgSecurityCampaignAlerts
          group={group}
          onGroupChange={onGroupChange}
          alertsPath={payload.alertsPath}
          alertsGroupsPath={payload.alertsGroupsPath}
          query={query}
          onStateFilterChange={onStateFilterChange}
          cursor={cursor}
          setCursor={onCursorChange}
          isCampaignClosed={!!closedAt}
        />
      </Box>
    </>
  )
}
