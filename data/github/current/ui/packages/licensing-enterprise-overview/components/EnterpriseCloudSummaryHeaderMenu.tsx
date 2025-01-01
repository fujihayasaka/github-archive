import {ActionList, ActionMenu, IconButton} from '@primer/react'
import {KebabHorizontalIcon} from '@primer/octicons-react'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'

export interface Props {
  isSelfServe: boolean
  isSelfServeBlocked: boolean
  isVolumeLicensed: boolean
  onManageSeatsSelect: () => void
}

export function EnterpriseCloudSummaryHeaderMenu({
  isSelfServe,
  isSelfServeBlocked,
  isVolumeLicensed,
  onManageSeatsSelect,
}: Props) {
  const {isStafftools} = useNavigation()

  const showManageLicenses = isVolumeLicensed && isSelfServe && !isSelfServeBlocked && !isStafftools

  if (!showManageLicenses) {
    return null // don't render the menu if there are no items
  }

  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <IconButton
          icon={KebabHorizontalIcon}
          variant="invisible"
          aria-label="Open menu"
          data-testid="ghe-summary-menu-button"
        />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay width="medium">
        <ActionList data-testid="ghe-summary-menu">
          <ActionList.Item onSelect={onManageSeatsSelect} data-testid="ghe-summary-menu-manage-seats-item">
            Manage licenses
          </ActionList.Item>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
