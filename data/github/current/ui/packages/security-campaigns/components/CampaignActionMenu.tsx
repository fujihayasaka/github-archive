import {ArchiveIcon, KebabHorizontalIcon, PencilIcon, PlayIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, type SxProp} from '@primer/react'

export interface CampaignActionMenuProps {
  onEditCampaignClicked: () => void
  onDeleteCampaignClicked: () => void
  onCloseCampaignClicked: () => void
  onReopenCampaignClicked: () => void
  isClosed: boolean
}

export function CampaignActionMenu({
  onEditCampaignClicked,
  onDeleteCampaignClicked,
  onCloseCampaignClicked,
  onReopenCampaignClicked,
  isClosed,
  sx,
}: CampaignActionMenuProps & SxProp) {
  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <IconButton icon={KebabHorizontalIcon} aria-label="Campaign options" sx={sx} />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay>
        <ActionList>
          {!isClosed && (
            <ActionList.Item onSelect={onEditCampaignClicked}>
              <PencilIcon /> Edit campaign
            </ActionList.Item>
          )}
          {!isClosed && (
            <ActionList.Item onSelect={onCloseCampaignClicked}>
              <ArchiveIcon /> Close campaign
            </ActionList.Item>
          )}
          {isClosed && (
            <ActionList.Item onSelect={onReopenCampaignClicked}>
              <PlayIcon /> Reopen campaign
            </ActionList.Item>
          )}
          <ActionList.Item variant="danger" onSelect={onDeleteCampaignClicked}>
            <TrashIcon /> Delete campaign
          </ActionList.Item>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
