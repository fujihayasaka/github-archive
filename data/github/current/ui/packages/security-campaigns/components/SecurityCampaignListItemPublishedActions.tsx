import {ActionList} from '@primer/react'
import {ListItemActionBar} from '@github-ui/list-view/ListItemActionBar'
import {ArchiveIcon, PlayIcon, TrashIcon} from '@primer/octicons-react'

export interface SecurityCampaignListItemPublishedActionsProps {
  campaignName: string
  disabled: boolean
  isClosed: boolean
  handleCloseCampaign: () => void
  handleReopenCampaign: () => void
  handleDeleteCampaign: () => void
}

export function SecurityCampaignListItemPublishedActions({
  campaignName,
  disabled,
  isClosed,
  handleReopenCampaign,
  handleCloseCampaign,
  handleDeleteCampaign,
}: SecurityCampaignListItemPublishedActionsProps) {
  return (
    <ListItemActionBar
      label={`${campaignName} campaign options`}
      staticMenuActions={[
        isClosed
          ? {
              key: 'reopen',
              render: () => (
                <ActionList.Item onSelect={handleReopenCampaign} disabled={disabled}>
                  <ActionList.LeadingVisual>
                    <PlayIcon />
                  </ActionList.LeadingVisual>
                  Reopen campaign
                </ActionList.Item>
              ),
            }
          : {
              key: 'close',
              render: () => (
                <ActionList.Item onSelect={handleCloseCampaign} disabled={disabled}>
                  <ActionList.LeadingVisual>
                    <ArchiveIcon />
                  </ActionList.LeadingVisual>
                  Close campaign
                </ActionList.Item>
              ),
            },
        {
          key: 'delete',
          render: () => (
            <ActionList.Item variant="danger" onSelect={handleDeleteCampaign} disabled={disabled}>
              <ActionList.LeadingVisual>
                <TrashIcon />
              </ActionList.LeadingVisual>
              Delete campaign
            </ActionList.Item>
          ),
        },
      ]}
    />
  )
}
