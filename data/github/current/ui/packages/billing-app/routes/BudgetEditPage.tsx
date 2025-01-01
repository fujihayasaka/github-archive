import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import Layout from '../components/Layout'
import BudgetForm from '../components/budget/BudgetForm'

import type {EditBudget} from '../types/budgets'
import type {AdminRole} from '../types/common'
import type {Product} from '../types/products'

export interface BudgetEditPagePayload {
  slug: string
  budget: EditBudget
  adminRoles: AdminRole[]
  enabledProducts: Product[]
  show_missing_payment_banner: boolean
  current_user_id: string
}

export function BudgetEditPage() {
  const payload = useRoutePayload<BudgetEditPagePayload>()
  const {show_missing_payment_banner: showMissingPaymentBanner, current_user_id: currentUserId} = payload

  return (
    <Layout>
      <BudgetForm
        budget={payload.budget}
        slug={payload.slug}
        adminRoles={payload.adminRoles}
        enabledProducts={payload.enabledProducts}
        showMissingPaymentBanner={showMissingPaymentBanner}
        currentUserId={currentUserId}
      />
    </Layout>
  )
}
