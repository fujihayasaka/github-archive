import {Stack} from '@primer/react'
import {CopilotIcon} from '@primer/octicons-react'
import type {Sku} from '@github-ui/licensing-common/copilot-types'
import {clsx} from 'clsx'
import styles from './Summary.module.css'

import {SummaryCard} from './SummaryCard'
import {CopilotUsageSummary} from '@github-ui/licensing-common/components/CopilotUsageSummary'
import {CopilotPaymentSummary} from '@github-ui/licensing-common/components/CopilotPaymentSummary'
import {SummaryHeaderButtons} from './SummaryHeaderButtons'
import {EnableCTA} from './EnableCTA'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'

export interface SummaryProps {
  isCopilotEnabled: boolean
  businessSlug: string
  copilotTocLink: string
  cfbHelpLink: string
  cfeHelpLink: string
  skus: Sku[]
  billingTermEndDate: string
  totalCost: number
}

export function Summary(props: SummaryProps) {
  const {isStafftools} = useNavigation()

  return (
    <SummaryCard
      headerIconComponent={CopilotIcon}
      title="Copilot"
      headerButtons={<SummaryHeaderButtons isStafftools={isStafftools} {...props} />}
    >
      {props.isCopilotEnabled ? (
        <Stack
          direction="horizontal"
          gap="spacious"
          className="px-4 pt-3 pb-0"
          align="stretch"
          data-testid="usage-payment-summary"
        >
          <CopilotUsageSummary skus={props.skus} />
          <div className={clsx(styles.divider)} />
          <CopilotPaymentSummary
            billingTermEndDate={props.billingTermEndDate}
            skus={props.skus}
            totalCost={props.totalCost}
          />
        </Stack>
      ) : isStafftools ? (
        <div className="ml-1 pl-7 pt-3 pb-0" data-testid="stafftools-copilot-disabled">
          Copilot is not enabled on this enterprise.
        </div>
      ) : (
        <EnableCTA {...props} />
      )}
    </SummaryCard>
  )
}
