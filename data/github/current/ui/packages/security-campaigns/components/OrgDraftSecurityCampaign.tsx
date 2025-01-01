import {useAlertFilterProviders} from '../hooks/use-alert-filter-providers'
import {ActionList, ActionMenu, Box, Button, Flash, IconButton, sx, Text, Tooltip} from '@primer/react'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
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
import {useCallback, useState} from 'react'
import {OrgDraftSecurityCampaignAlerts} from './OrgDraftSecurityCampaignAlerts'
import {OrgDraftProgressMetric} from './OrgDraftProgressMetric'
import DataCard from '@github-ui/data-card'
import {useDeleteSecurityCampaignMutation} from '../hooks/use-delete-security-campaign-mutation'
import {KebabHorizontalIcon, PencilIcon, TrashIcon} from '@primer/octicons-react'
import {useNavigate} from '@github-ui/use-navigate'
import {DeleteCampaignConfirmationDialog} from './DeleteCampaignConfirmationDialog'
import {OrgDraftAutofixSupportedMetric} from './OrgDraftAutofixSupportedMetric'
import type {SecurityCampaignForm} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import {UpsertDraftSecurityCampaignFormDialog} from './UpsertDraftSecurityCampaignFormDialog'
import {useEditDraftSecurityCampaignMutation} from '../hooks/use-edit-draft-security-campaign-mutation'
import {OrgSecurityCampaignHeading} from './OrgSecurityCampaignHeading'
import {OrgDraftAlertsFilter} from './OrgDraftAlertsFilter'
import {CampaignFeedbackLink} from './CampaignFeedbackLink'

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
    openOrgCampaignsCount,
    maxCampaigns,
    maxAlerts,
    campaignsGAEnabled,
  } = payload

  const [campaign, setCampaign] = useState(payload.campaign)
  const campaignsLimitReached = (openOrgCampaignsCount ?? 0) >= maxCampaigns

  // Draft campaigns should always have a creation query but setting a default
  // value to satisfy the type checker
  const [query, setQuery] = useState(campaign.creationQuery || 'is:open')

  const filterProviders = useAlertFilterProviders({
    organizationLogin,
    showNewAutofixFilters,
    customPropertyNames,
  })

  const {cursor, group, onCursorChange, onGroupChange, onStateFilterChange} = useAlertsParams({
    initialGroup: 'none',
  })

  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)

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
          onSuccess: () => {
            setCampaign(oldCampaign => ({...oldCampaign, ...updatedCampaign}))
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

  const navigate = useNavigate()
  const deleteCampaign = async () => {
    mutateDelete(undefined, {
      onSuccess: () => {
        navigate(securityCampaignOrgCampaignsPath({org: organizationLogin, state: 'draft'}))
      },
      onError: () => {
        setIsDeleteConfirmationDialogOpen(false)
      },
    })
  }

  const alertsPath = codeScanningOrgAlertListPath({org: organizationLogin})

  const handleStateFilterChange = (state: 'open' | 'closed') => {
    onStateFilterChange(state)

    const queryWithoutState = query.replaceAll(/is:(open|closed)/g, '').trim()
    setQuery(`is:${state} ${queryWithoutState}`.trim())
  }

  const reviewAndPublishButton = (
    <Button
      onClick={() => {
        if (!campaignsLimitReached) {
          navigate(
            securityCampaignOrgDraftCampaignPublishPath({
              org: organizationLogin,
              securityCampaignNumber: campaign.number,
            }),
          )
        }
      }}
      size="medium"
      inactive={campaignsLimitReached}
      variant="primary"
    >
      Review and publish campaign
    </Button>
  )

  return (
    <>
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
      <Box
        sx={{display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 2}}
        className="border-bottom pb-2 mb-2"
      >
        <OrgSecurityCampaignHeading
          campaignName={campaign.name}
          userManagers={campaign.managers}
          teamManagers={campaign.teamManagers}
          contactLink={campaign.contactLink}
          isDraft
        />
        <Box sx={{display: 'flex', alignItems: 'center', gap: 2}}>
          {campaignsGAEnabled ? (
            <CampaignFeedbackLink />
          ) : (
            <BetaLabel feedbackUrl="https://gh.io/security-campaigns-feedback" />
          )}
          {showCampaignManagementActions && (
            <>
              {campaignsLimitReached ? (
                <Tooltip text={`Limit of ${maxCampaigns} campaigns is reached`} direction="n">
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
        </Box>
      </Box>
      <Text as="p" sx={{color: 'fg.muted'}}>
        {campaign.description}
      </Text>
      <Box sx={{display: 'flex', gap: 2, flexWrap: 'wrap'}} data-testid="org-draft-security-campaign-metrics">
        <OrgDraftProgressMetric alertsPath={alertsPath} query={query} maxAlerts={maxAlerts} />
        <DataCard cardTitle="Status">
          <div>
            <div className="f2 lh-condensed-ultra text-normal">Draft</div>
          </div>
          <DataCard.Description>
            <>The campaign is not published yet.</>
          </DataCard.Description>
        </DataCard>
        <OrgDraftAutofixSupportedMetric alertsPath={alertsPath} query={query} />
      </Box>
      <OrgDraftAlertsFilter
        providers={filterProviders}
        query={query}
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
      />
    </>
  )
}
