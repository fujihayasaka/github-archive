import {Heading, Label} from '@primer/react'
import {formatMoneyDisplay} from '../../utils/money'
import type {Customer} from '../../types/common'
import pluralize from 'pluralize'
import styles from './PlanCard.module.css'

interface CurrentPlanCardProps {
  customer: Customer
}

export default function CurrentPlanCard({customer}: CurrentPlanCardProps) {
  const isFreePlan = customer.plan.startsWith('free_')
  const isProPlan = customer.plan === 'pro'
  const notFreeOrProPlan = !isFreePlan && !isProPlan

  const getPlanName = (plan: string): string => {
    if (plan.startsWith('free_')) {
      return 'GitHub Free'
    }
    switch (plan) {
      case 'team':
        return 'GitHub Team'
      case 'pro':
        return 'GitHub Pro'
      default:
        return 'N/A'
    }
  }

  return (
    <div className={styles.card} data-testid="current-plan-card">
      <div className={styles.planCard}>
        <div>
          <div className={styles.headingSection}>
            <Heading as="h2" className={styles.cardHeading}>
              {getPlanName(customer.plan)}
            </Heading>
            {customer.hasPendingPlanChange && <Label className={styles.downgradeLabel}>Downgrade Pending</Label>}
          </div>
          <div className={styles.moneyContainer} data-testid="bill-section">
            <div>
              <span className={styles.moneyAmount}>{formatMoneyDisplay(customer.paymentAmount, 2, true)}</span>
              <span className={styles.perPeriod}>per {customer.planDuration}</span>
            </div>
          </div>
        </div>
      </div>

      {notFreeOrProPlan && (
        <p className={styles.subtext} data-testid="licenses-section">
          <span className={styles.bold}>{customer.seats}</span> {pluralize('license', customer.seats)} -
          <span className={styles.bold}>{formatMoneyDisplay(customer.pricePerSeat)}</span> per user/
          {customer.planDuration}
        </p>
      )}
    </div>
  )
}
