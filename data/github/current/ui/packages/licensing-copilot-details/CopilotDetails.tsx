import {Stack} from '@primer/react'
import {CopilotUsageSummary} from '@github-ui/licensing-common/components/CopilotUsageSummary'
import {CopilotPaymentSummary} from '@github-ui/licensing-common/components/CopilotPaymentSummary'
import type {Sku} from '@github-ui/licensing-common/copilot-types'
import {clsx} from 'clsx'
import styles from './CopilotDetails.module.css'

export interface CopilotDetailsProps {
  copilot: {
    skus: Sku[]
    billingTermEndDate: string
    totalCost: number
  }
}

export function CopilotDetails({copilot}: CopilotDetailsProps) {
  return (
    <div className={'mb-4'} data-testid="licensing-copilot-details">
      <Stack
        direction="horizontal"
        gap="spacious"
        className="px-4 pt-3 pb-0"
        align="stretch"
        data-testid="copilot-details"
      >
        <div className={clsx('Box', styles.box, 'p-3', styles.border)}>
          <CopilotUsageSummary skus={copilot.skus} />
        </div>
        <div className={clsx('Box', styles.box, 'p-3', styles.border)}>
          <CopilotPaymentSummary
            billingTermEndDate={copilot.billingTermEndDate}
            skus={copilot.skus}
            totalCost={copilot.totalCost}
          />
        </div>
      </Stack>
    </div>
  )
}
