import {Heading, Label} from '@primer/react'
import {formatMoneyDisplay} from '../../utils/money'
import styles from './PlanCard.module.css'
import type {CopilotForIndividualsData} from '../../types/copilot-for-individuals'

interface CopilotPlanCardProps {
  copilotForIndividualsData: CopilotForIndividualsData
}

export default function CopilotPlanCard({copilotForIndividualsData}: CopilotPlanCardProps) {
  const {onFreeTier, subscriptionItem} = copilotForIndividualsData

  const getProductName = (): string => {
    if (onFreeTier) {
      return 'Copilot Free'
    }
    switch (subscriptionItem?.name) {
      case 'GitHub Copilot Pro+':
        return 'Copilot Pro+'
      default:
        return 'Copilot Pro'
    }
  }

  const getPrice = (): number => {
    if (subscriptionItem != null) {
      return subscriptionItem.price
    }
    return 0
  }

  const getBillingCycle = (): string => {
    if (subscriptionItem != null) {
      return subscriptionItem.billingCycle
    }
    return 'month'
  }

  return (
    <div className={styles.card} data-testid="copilot-plan-card">
      <div className={styles.planCard}>
        <div>
          <div className={styles.headingSection}>
            <Heading as="h3" className={styles.cardHeading}>
              {getProductName()}
            </Heading>
            {subscriptionItem?.hasPendingDowngrade && (
              <Label className={styles.downgradeLabel}>Downgrade Pending</Label>
            )}
          </div>
          <div className={styles.moneyContainer} data-testid="bill-section">
            <div>
              <span className={styles.moneyAmount}>{formatMoneyDisplay(getPrice(), 2, true)}</span>
              <span className={styles.perPeriod}>per {getBillingCycle()}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
