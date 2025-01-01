import {ActionList, ActionMenu, IconButton} from '@primer/react'
import {KebabHorizontalIcon} from '@primer/octicons-react'

import type {InvoiceLicenseInfo} from '@github-ui/licensing-common/types/invoice-license-info'
import type {TrialInfo} from '@github-ui/licensing-common/types/trial-info'
import type {Sku} from '../types/sku'

export interface Props {
  eligibleForTrial: boolean
  isSelfServeAdvancedSecurity: boolean
  invoiceLicenseInfo?: InvoiceLicenseInfo
  isTeams: boolean
  skus: Sku[]
  trialInfo?: TrialInfo
  onManageSeatsSelect: () => void
  onCancelSubscriptionSelect: () => void
}

export function AdvancedSecuritySummaryHeaderMenu(props: Props) {
  const shouldRenderMenu =
    !props.trialInfo &&
    !props.eligibleForTrial &&
    !props.invoiceLicenseInfo &&
    !props.isTeams &&
    props.isSelfServeAdvancedSecurity

  if (!shouldRenderMenu) {
    return null
  }

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
