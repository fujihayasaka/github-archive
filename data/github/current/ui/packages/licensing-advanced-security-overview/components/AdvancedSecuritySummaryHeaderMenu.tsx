import {ActionList, ActionMenu, IconButton} from '@primer/react'
import {KebabHorizontalIcon} from '@primer/octicons-react'

export interface Props {
  onManageSeatsSelect: () => void
  onCancelSubscriptionSelect: () => void
}

export function AdvancedSecuritySummaryHeaderMenu(props: Props) {
  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <IconButton
          icon={KebabHorizontalIcon}
          variant="invisible"
          aria-label="Open menu"
          data-testid="ghas-summary-menu-button"
        />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay width="medium">
        <ActionList data-testid="ghas-summary-menu">
          <ActionList.Item onSelect={props.onManageSeatsSelect} data-testid="ghas-summary-menu-manage-seats-item">
            Manage licenses
          </ActionList.Item>
          <ActionList.Item
            onSelect={props.onCancelSubscriptionSelect}
            data-testid="ghas-summary-menu-cancel-subscription-item"
          >
            Cancel subscription
          </ActionList.Item>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
