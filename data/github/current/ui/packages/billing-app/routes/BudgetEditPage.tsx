import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import Layout from '../components/Layout'
import BudgetForm from '../components/budget/BudgetForm'

import type {EditBudget} from '../types/budgets'
import type {AdminRole} from '../types/common'
import type {Product} from '../types/products'
import type {PricingDetails} from '../types/pricings'

export interface BudgetEditPagePayload {
  slug: string
  budget: EditBudget
  adminRoles: AdminRole[]
  enabledProducts: Product[]
  enabledSkus: PricingDetails[]
  show_missing_payment_banner: boolean
  current_user_id: string
  billing_coding_agent_enabled?: boolean
  billing_spark_enabled?: boolean
}

export function BudgetEditPage() {
  const payload = useRoutePayload<BudgetEditPagePayload>()
  const {
    show_missing_payment_banner: showMissingPaymentBanner,
    current_user_id: currentUserId,
    billing_coding_agent_enabled: codingAgentEnabled = false,
    billing_spark_enabled: sparkEnabled = false,
  } = payload

  return (
    <Layout>
      <BudgetForm
        budget={payload.budget}
        slug={payload.slug}
        adminRoles={payload.adminRoles}
        enabledProducts={payload.enabledProducts}
        enabledSkus={payload.enabledSkus}
        showMissingPaymentBanner={showMissingPaymentBanner}
        currentUserId={currentUserId}
        codingAgentEnabled={codingAgentEnabled}
        sparkEnabled={sparkEnabled}
      />
    </Layout>
  )
}
