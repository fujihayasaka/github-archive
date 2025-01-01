import {ActionList, ActionMenu, IconButton} from '@primer/react'
import {KebabHorizontalIcon} from '@primer/octicons-react'
import {useNavigation} from '../contexts/NavigationContext'

export interface Props {
  isCsvDownloadDisabled: boolean
  isSelfServe: boolean
  isSelfServeBlocked: boolean
  isVolumeLicensed: boolean
  onDownloadCsvSelect: () => void
  onManageSeatsSelect: () => void
}

export function EnterpriseCloudSummaryHeaderMenu(props: Props) {
  const {isStafftools} = useNavigation()

  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
        <IconButton
          icon={KebabHorizontalIcon}
          variant="invisible"
          aria-label="Open menu"
          data-testid="ghe-summary-menu-button"
          unsafeDisableTooltip
        />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay width="medium">
        <ActionList data-testid="ghe-summary-menu">
          <ActionList.Item
            onSelect={props.onDownloadCsvSelect}
            disabled={props.isCsvDownloadDisabled}
            data-testid="ghe-summary-menu-download-item"
          >
            Download CSV report
          </ActionList.Item>
          {props.isVolumeLicensed && props.isSelfServe && !props.isSelfServeBlocked && !isStafftools && (
            <ActionList.Item onSelect={props.onManageSeatsSelect} data-testid="ghe-summary-menu-manage-seats-item">
              Manage seats
            </ActionList.Item>
          )}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
