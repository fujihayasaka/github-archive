import {Heading, Link} from '@primer/react'
import {useParams} from 'react-router-dom'
import type {Customer} from '../../types/common'
import CurrentPlanCard from './CurrentPlanCard'
import CopilotPlanCard from './CopilotPlanCard'
import {PageContext} from '../../App'
import {useContext} from 'react'
import styles from './SubscriptionsContainer.module.css'
import type {CopilotForIndividualsData} from '../../types/copilot-for-individuals'

interface CurrentPlanCardProps {
  customer: Customer
  copilotForIndividualsData: CopilotForIndividualsData
}

export default function SubscriptionsContainer({customer, copilotForIndividualsData}: CurrentPlanCardProps) {
  const {organization} = useParams()
  const {isOrganizationRoute} = useContext(PageContext)
  const licensingUrl = isOrganizationRoute
    ? `/organizations/${organization}/settings/licensing`
    : `/settings/billing/licensing`
  const hasCopilotForIndividual =
    copilotForIndividualsData.subscriptionItem != null || copilotForIndividualsData.onFreeTier

  return (
    <div data-testid="billing-subscriptions-section">
      <div className={styles.titleSection}>
        <Heading as="h3" className={styles.heading}>
          Subscriptions
        </Heading>
        <div className={styles.columnReverse}>
          <Link href={licensingUrl} className={styles.links}>
            Manage subscriptions
          </Link>
        </div>
      </div>
      <div className={hasCopilotForIndividual ? styles.responsiveGrid : styles.grid}>
        <CurrentPlanCard customer={customer} />
        {hasCopilotForIndividual && <CopilotPlanCard copilotForIndividualsData={copilotForIndividualsData} />}
      </div>
    </div>
  )
}
