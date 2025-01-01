import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

import {ErrorComponent} from '../components'
import BudgetForm from '../components/budget/BudgetForm'
import Layout from '../components/Layout'

import type {AdminRole} from '../types/common'
import type {Product} from '../types/products'
import type {PricingDetails} from '../types/pricings'

export interface BudgetNewPagePayload {
  slug: string
  current_user_id: string
  adminRoles: AdminRole[]
  enabledProducts: Product[]
  enabledSkus: PricingDetails[]
  show_missing_payment_banner: boolean
  show_models_banner: boolean
  billing_coding_agent_enabled?: boolean
  billing_spark_enabled?: boolean
}

export function BudgetNewPage() {
  const payload = useRoutePayload<BudgetNewPagePayload>()
  const {
    enabledProducts,
    enabledSkus,
    slug,
    current_user_id,
    adminRoles,
    show_missing_payment_banner: showMissingPaymentBanner,
    show_models_banner: showModelsBanner,
    billing_coding_agent_enabled: codingAgentEnabled = false,
    billing_spark_enabled: sparkEnabled = false,
  } = payload

  return (
    <Layout>
      {enabledProducts.length > 0 ? (
        <BudgetForm
          slug={slug}
          currentUserId={current_user_id}
          adminRoles={adminRoles}
          enabledProducts={enabledProducts}
          enabledSkus={enabledSkus}
          showMissingPaymentBanner={showMissingPaymentBanner}
          showModelsBanner={showModelsBanner}
          codingAgentEnabled={codingAgentEnabled}
          sparkEnabled={sparkEnabled}
        />
      ) : (
        <ErrorComponent sx={{border: 0}} testid="new-budget-form-loading-error" text="Something went wrong" />
      )}
    </Layout>
  )
}
