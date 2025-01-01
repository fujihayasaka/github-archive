import {ActionList} from '@primer/react'
import {ListItemActionBar} from '@github-ui/list-view/ListItemActionBar'
import {GoalIcon, TrashIcon} from '@primer/octicons-react'

export interface SecurityCampaignListItemDraftActionsProps {
  campaignName: string
  disabled: boolean
  maxOpenCampaigns: number
  openCampaignsCount: number
  hasOpenSpam: boolean
  handleDeleteDraftCampaign: () => void
  handlePublishCampaign: () => void
}

export function SecurityCampaignListItemDraftActions({
  campaignName,
  disabled,
  maxOpenCampaigns,
  openCampaignsCount,
  hasOpenSpam,
  handleDeleteDraftCampaign,
  handlePublishCampaign,
}: SecurityCampaignListItemDraftActionsProps) {
  const maxOpenCampaignsReached = openCampaignsCount >= maxOpenCampaigns
  return (
    <ListItemActionBar
      label={`${campaignName} campaign options`}
      staticMenuActions={[
        {
          key: 'publish',
          render: () => (
            <ActionList.Item
              onSelect={handlePublishCampaign}
              disabled={disabled}
              inactiveText={
                maxOpenCampaignsReached
                  ? `Limit of ${maxOpenCampaigns} open ${hasOpenSpam ? 'and spam ' : ''}campaigns has been reached`
                  : undefined
              }
            >
              <ActionList.LeadingVisual>
                <GoalIcon />
              </ActionList.LeadingVisual>
              Publish campaign
            </ActionList.Item>
          ),
        },
        {
          key: 'delete-draft',
          render: () => (
            <ActionList.Item variant="danger" onSelect={handleDeleteDraftCampaign} disabled={disabled}>
              <ActionList.LeadingVisual>
                <TrashIcon />
              </ActionList.LeadingVisual>
              Delete draft
            </ActionList.Item>
          ),
        },
      ]}
    />
  )
}
