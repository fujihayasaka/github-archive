import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ArchiveIcon, GoalIcon, IssueDraftIcon} from '@primer/octicons-react'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {useBannerContext} from '@github-ui/role-assignments/banner-provider'
import {useCallback, useState} from 'react'
import {useDeleteSecurityCampaignMutation} from '../hooks/use-delete-security-campaign-mutation'
import {useReopenSecurityCampaignMutation} from '../hooks/use-reopen-security-campaign-mutation'
import {DeleteCampaignConfirmationDialog} from './DeleteCampaignConfirmationDialog'
import {CampaignProgressBar} from './CampaignProgressBar'

import styles from './SecurityCampaignListItem.module.css'
import {useCloseSecurityCampaignMutation} from '../hooks/use-close-security-campaign-mutation'
import {SecurityCampaignListItemDescription} from './SecurityCampaignListItemDescription'
import {calculateStatus} from '../utils/calculate-status'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'
import {
  securityCampaignOrgDeleteDraftPath,
  securityCampaignOrgCampaignClosePath,
  securityCampaignOrgCampaignDeletePath,
  securityCampaignOrgCampaignPath,
  securityCampaignOrgCampaignReopenPath,
  securityCampaignOrgDraftCampaignPublishPath,
} from '@github-ui/paths'
import {isCampaignWithCounts} from '../utils/is-campaign-with-counts'
import {SecurityCampaignListItemPublishedActions} from './SecurityCampaignListItemPublishedActions'
import {SecurityCampaignListItemDraftActions} from './SecurityCampaignListItemDraftActions'
import {useNavigate} from '@github-ui/use-navigate'
import {useQueryClient} from '@github-ui/react-query'
import type {SecurityCampaign, SecurityCampaignWithCounts} from '../types/security-campaign'

export interface SecurityCampaignListItemProps {
  organizationLogin: string
  campaign: SecurityCampaignWithCounts | SecurityCampaign
  maxOpenCampaigns: number
  openCampaignsCount: number
  hasOpenSpam: boolean
  allowActions: boolean
  showLeadingIcon?: boolean
  showManagers?: boolean
  onMutationError: (error: string) => void
}

export function SecurityCampaignListItem({
  organizationLogin,
  campaign,
  maxOpenCampaigns,
  openCampaignsCount,
  hasOpenSpam,
  allowActions,
  showLeadingIcon = false,
  showManagers = false,
  onMutationError,
}: SecurityCampaignListItemProps) {
  const [isDeleteConfirmationDialogOpen, setIsDeleteConfirmationDialogOpen] = useState(false)
  const navigate = useNavigate()
  const {showBanner} = useBannerContext()
  const queryClient = useQueryClient()

  const isDraft = !campaign.publishedAt

  const invalidateQueries = useCallback(() => {
    // This will refetch the campaigns list
    void queryClient.invalidateQueries({
      queryKey: ['campaigns-list'],
    })

    void queryClient.invalidateQueries({
      queryKey: ['campaigns-counts'],
    })
  }, [queryClient])

  const {
    mutate: mutateClose,
    isPending: isClosePending,
    isSuccess: isCloseSuccess,
  } = useCloseSecurityCampaignMutation(
    securityCampaignOrgCampaignClosePath({
      org: organizationLogin,
      securityCampaignNumber: campaign.number,
    }),
  )

  const handleCloseCampaign = useCallback(() => {
    mutateClose(undefined, {
      onSuccess: response => {
        if (response.showFlashMessage) {
          showBanner({
            message: `The campaign ${campaign.name} was successfully closed.`,
            variant: 'success',
          })
          invalidateQueries()
        } else {
          // window.location.reload is used instead of invalidating the query as invalidating the query does not show
          // the flash message
          window.location.reload()
        }
      },
      onError: error => {
        onMutationError(`Unable to close campaign "${campaign.name}": ${error.message}`)
      },
    })
  }, [campaign.name, mutateClose, onMutationError, showBanner, invalidateQueries])

  const {
    mutate: mutateReopen,
    isPending: isReopenPending,
    isSuccess: isReopenSuccess,
  } = useReopenSecurityCampaignMutation(
    securityCampaignOrgCampaignReopenPath({
      org: organizationLogin,
      securityCampaignNumber: campaign.number,
    }),
  )

  const handleReopenCampaign = useCallback(() => {
    mutateReopen(undefined, {
      onSuccess: response => {
        if (response.showFlashMessage) {
          showBanner({
            message: `The campaign ${campaign.name} was successfully reopened.`,
            variant: 'success',
          })
          invalidateQueries()
        } else {
          // window.location.reload is used instead of invalidating the query as invalidating the query does not show
          // the flash message
          window.location.reload()
        }
      },
      onError: error => {
        onMutationError(`Unable to reopen campaign "${campaign.name}": ${error.message}`)
      },
    })
  }, [campaign.name, mutateReopen, onMutationError, showBanner, invalidateQueries])

  const deletePath = isDraft
    ? securityCampaignOrgDeleteDraftPath({
        org: organizationLogin,
        securityCampaignNumber: campaign.number,
      })
    : securityCampaignOrgCampaignDeletePath({
        org: organizationLogin,
        securityCampaignNumber: campaign.number,
      })

  const {
    mutate: mutateDelete,
    isPending: isDeletePending,
    isSuccess: isDeleteSuccess,
  } = useDeleteSecurityCampaignMutation(deletePath)

  const handleDeleteCampaign = useCallback(() => {
    mutateDelete(undefined, {
      onSuccess: response => {
        if (response.showFlashMessage) {
          showBanner({
            message: `The campaign ${campaign.name} was successfully deleted.`,
            variant: 'success',
          })
          invalidateQueries()
        } else {
          // Need to do a full page reload so that the sidebar numbers (which are not in react) get updated.
          // Unfortunately this makes the campaigns list go back to page one, but that's a tradeoff.
          window.location.reload()
        }
      },
      onError: error => {
        setIsDeleteConfirmationDialogOpen(false)
        onMutationError(`Unable to delete ${isDraft ? 'draft ' : ''}campaign "${campaign.name}": ${error.message}`)
      },
    })
  }, [campaign.name, isDraft, mutateDelete, onMutationError, showBanner, invalidateQueries])

  const areActionsDisabled =
    isReopenPending ||
    isReopenSuccess ||
    isClosePending ||
    isCloseSuccess ||
    isDeletePending ||
    isDeleteSuccess ||
    isDeleteConfirmationDialogOpen

  const campaignIcon = () => {
    if (isDraft) {
      return <IssueDraftIcon className="fgColor-muted" />
    }
    if (campaign.closedAt) {
      return <ArchiveIcon className="fgColor-muted" />
    }
    return <GoalIcon className="fgColor-muted" />
  }

  const listItemActions = () => {
    if (!allowActions) return undefined

    if (isDraft) {
      return (
        <SecurityCampaignListItemDraftActions
          campaignName={campaign.name}
          disabled={areActionsDisabled}
          maxOpenCampaigns={maxOpenCampaigns}
          openCampaignsCount={openCampaignsCount}
          hasOpenSpam={hasOpenSpam}
          handleDeleteDraftCampaign={() => setIsDeleteConfirmationDialogOpen(true)}
          handlePublishCampaign={() => {
            navigate(
              securityCampaignOrgDraftCampaignPublishPath({
                org: organizationLogin,
                securityCampaignNumber: campaign.number,
              }),
            )
          }}
        />
      )
    } else {
      return (
        <SecurityCampaignListItemPublishedActions
          campaignName={campaign.name}
          disabled={areActionsDisabled}
          isClosed={!!campaign.closedAt}
          handleReopenCampaign={handleReopenCampaign}
          handleCloseCampaign={handleCloseCampaign}
          handleDeleteCampaign={() => setIsDeleteConfirmationDialogOpen(true)}
        />
      )
    }
  }

  return (
    <>
      <ListItem
        title={
          <ListItemTitle
            href={securityCampaignOrgCampaignPath({
              org: organizationLogin,
              securityCampaignNumber: campaign.number,
            })}
            value={`${campaign.name}`}
            headingClassName={styles.ListItemTitle_0}
            containerClassName={styles.ListItemTitle_1}
          />
        }
        metadata={
          !isDraft &&
          isCampaignWithCounts(campaign) && (
            <ListItemMetadata alignment="right" variant="primary">
              <CampaignProgressBar
                openCount={campaign.openCount}
                closedCount={campaign.closedCount}
                openWithLinksCount={campaign.openWithLinksCount}
              />
            </ListItemMetadata>
          )
        }
        secondaryActions={listItemActions()}
        className={styles.ListItem_0}
      >
        {showLeadingIcon && (
          <ListItemLeadingContent>
            <ListItemLeadingVisual>{campaignIcon()}</ListItemLeadingVisual>
          </ListItemLeadingContent>
        )}

        <ListItemMainContent>
          <SecurityCampaignListItemDescription
            campaign={campaign}
            status={calculateStatus(campaign)}
            showManagers={showManagers}
          />
        </ListItemMainContent>
      </ListItem>
      {isDeleteConfirmationDialogOpen && (
        <DeleteCampaignConfirmationDialog
          setIsOpen={setIsDeleteConfirmationDialogOpen}
          deleteCampaign={handleDeleteCampaign}
          disabled={isDeletePending || isDeleteSuccess}
          isDraft={isDraft}
          campaignName={campaign.name}
        />
      )}
    </>
  )
}
