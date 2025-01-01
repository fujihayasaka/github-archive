import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import type {SecurityCampaign, SecurityCampaignWithCounts} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import {ArchiveIcon, GoalIcon, IssueDraftIcon} from '@primer/octicons-react'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
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

export interface SecurityCampaignListItemProps {
  organizationLogin: string
  campaign: SecurityCampaignWithCounts | SecurityCampaign
  maxOpenCampaigns: number
  openCampaignsCount: number
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
  allowActions,
  showLeadingIcon = false,
  showManagers = false,
  onMutationError,
}: SecurityCampaignListItemProps) {
  const [isDeleteConfirmationDialogOpen, setIsDeleteConfirmationDialogOpen] = useState(false)
  const navigate = useNavigate()

  const isDraft = !campaign.publishedAt

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
      onSuccess: () => {
        // window.location.reload is used instead of invalidating the query as invalidating the query does not show
        // the flash message
        window.location.reload()
      },
      onError: error => {
        onMutationError(`Unable to close campaign "${campaign.name}": ${error.message}`)
      },
    })
  }, [campaign.name, mutateClose, onMutationError])

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
      onSuccess: () => {
        // window.location.reload is used instead of invalidating the query as invalidating the query does not show
        // the flash message
        window.location.reload()
      },
      onError: error => {
        onMutationError(`Unable to reopen campaign "${campaign.name}": ${error.message}`)
      },
    })
  }, [campaign.name, mutateReopen, onMutationError])

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
      onSuccess: () => {
        // Need to do a full page reload so that the sidebar numbers (which are not in react) get updated.
        // Unfortunately this makes the campaigns list go back to page one, but that's a tradeoff.
        window.location.reload()
      },
      onError: error => {
        setIsDeleteConfirmationDialogOpen(false)
        onMutationError(`Unable to delete ${isDraft ? 'draft ' : ''}campaign "${campaign.name}": ${error.message}`)
      },
    })
  }, [campaign.name, isDraft, mutateDelete, onMutationError])

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
          disabled={areActionsDisabled}
          maxOpenCampaigns={maxOpenCampaigns}
          openCampaignsCount={openCampaignsCount}
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
