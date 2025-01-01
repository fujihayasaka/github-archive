import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import type {SecurityCampaignWithCounts} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import {ActionList, RelativeTime} from '@primer/react'
import {ListItemActionBar} from '@github-ui/list-view/ListItemActionBar'
import {PlayIcon, TrashIcon} from '@primer/octicons-react'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {useCallback, useState} from 'react'
import {useDeleteSecurityCampaignMutation} from '../hooks/use-delete-security-campaign-mutation'
import {useReopenSecurityCampaignMutation} from '../hooks/use-reopen-security-campaign-mutation'
import {DeleteCampaignConfirmationDialog} from './DeleteCampaignConfirmationDialog'
import {CampaignProgressBar} from './CampaignProgressBar'

export interface ClosedSecurityCampaignListItemProps {
  campaign: SecurityCampaignWithCounts
  onMutationError: (error: string) => void
}

export function ClosedSecurityCampaignListItem({campaign, onMutationError}: ClosedSecurityCampaignListItemProps) {
  const [isDeleteConfirmationDialogOpen, setIsDeleteConfirmationDialogOpen] = useState(false)

  const {
    mutate: mutateReopen,
    isPending: isReopenPending,
    isSuccess: isReopenSuccess,
  } = useReopenSecurityCampaignMutation(campaign.reopenPath)

  const handleReopenCampaign = useCallback(() => {
    mutateReopen(undefined, {
      onSuccess: response => {
        // eslint-disable-next-line react-compiler/react-compiler
        window.location.href = response.redirect // This is used instead of navigate as navigate does not show the flash message
      },
      onError: error => {
        onMutationError(`Unable to reopen campaign "${campaign.name}": ${error.message}`)
      },
    })
  }, [campaign.name, mutateReopen, onMutationError])

  const {
    mutate: mutateDelete,
    isPending: isDeletePending,
    isSuccess: isDeleteSuccess,
  } = useDeleteSecurityCampaignMutation(campaign.deletePath)

  const handleDeleteCampaign = useCallback(() => {
    mutateDelete(undefined, {
      onSuccess: () => {
        // Need to do a full page reload so that the sidebar numbers (which are not in react) get updated.
        // Unfortunately this makes the closed campaigns list go back to page one, but that's a tradeoff.
        window.location.reload()
      },
      onError: error => {
        setIsDeleteConfirmationDialogOpen(false)
        onMutationError(`Unable to delete campaign "${campaign.name}": ${error.message}`)
      },
    })
  }, [campaign.name, mutateDelete, onMutationError])

  return (
    <>
      <ListItem
        sx={{pl: 2}}
        title={
          <ListItemTitle
            href={campaign.showPath}
            value={`${campaign.name}`}
            headingSx={{
              maxWidth: '100%',
              whiteSpace: 'nowrap',
            }}
            containerSx={{display: 'flex', alignItems: 'flex-start', gap: 1, maxWidth: '100%'}}
          />
        }
        metadata={
          <ListItemMetadata alignment="right" variant="primary">
            <CampaignProgressBar
              openCount={campaign.openCount}
              closedCount={campaign.closedCount}
              openWithLinksCount={campaign.openWithLinksCount}
            />
          </ListItemMetadata>
        }
        secondaryActions={
          <ListItemActionBar
            label="campaign options"
            staticMenuActions={[
              {
                key: 'reopen',
                render: () => (
                  <ActionList.Item onSelect={handleReopenCampaign} disabled={isReopenPending || isReopenSuccess}>
                    <ActionList.LeadingVisual>
                      <PlayIcon />
                    </ActionList.LeadingVisual>
                    Re-open campaign
                  </ActionList.Item>
                ),
              },
              {
                key: 'delete',
                render: () => (
                  <ActionList.Item
                    variant="danger"
                    onSelect={() => setIsDeleteConfirmationDialogOpen(true)}
                    disabled={isDeleteConfirmationDialogOpen || isDeletePending || isReopenSuccess}
                  >
                    <ActionList.LeadingVisual>
                      <TrashIcon />
                    </ActionList.LeadingVisual>
                    Delete campaign
                  </ActionList.Item>
                ),
              },
            ]}
          />
        }
      >
        <ListItemMainContent>
          <ListItemDescription>
            {`Closed `}
            <RelativeTime datetime={campaign.closedAt ?? undefined} />
          </ListItemDescription>
        </ListItemMainContent>
      </ListItem>
      {isDeleteConfirmationDialogOpen && (
        <DeleteCampaignConfirmationDialog
          setIsOpen={setIsDeleteConfirmationDialogOpen}
          deleteCampaign={handleDeleteCampaign}
          disabled={isDeletePending || isDeleteSuccess}
        />
      )}
    </>
  )
}
