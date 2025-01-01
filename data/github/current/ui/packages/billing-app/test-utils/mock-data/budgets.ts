import {BudgetLimitTypes} from '../../enums/budgets'
import type {BudgetsPagePayload} from '../../routes/BudgetsPage'

import {BudgetPricingTargetType, type Budget} from '../../types/budgets'
import {USER_CUSTOMER} from './customers'

export const MOCK_BUDGETS: Budget[] = [
  {
    targetType: 'Org',
    targetAmount: 10.0,
    budgetLimitType: BudgetLimitTypes.AlertingOnly,
    currentAmount: 9.0,
    targetId: '1',
    targetName: 'github-inc',
    uuid: 'test-uuid',
    alertEnabled: true,
    pricingTargetType: BudgetPricingTargetType.ProductPricing,
    pricingTargetId: 'actions',
  },
]

export const MOCK_BUDGETS_TO_FILTER: Budget[] = [
  {
    targetType: 'Repo',
    targetAmount: 1,
    budgetLimitType: BudgetLimitTypes.PreventFurtherUsage,
    currentAmount: 0,
    targetName: 'billing-test-org/test-repo',
    alertEnabled: true,
    targetId: 'R_kgAQ',
    pricingTargetType: BudgetPricingTargetType.ProductPricing,
    pricingTargetId: 'actions',
    uuid: 'ab50848c-2519-40a5-b73c-c988bfc69fec',
  },
  {
    targetType: 'CustomerResource',
    targetAmount: 1,
    budgetLimitType: BudgetLimitTypes.PreventFurtherUsage,
    currentAmount: 0,
    targetName: 'billing-test-org',
    alertEnabled: true,
    targetId: '11',
    pricingTargetType: BudgetPricingTargetType.ProductPricing,
    pricingTargetId: 'actions',
    uuid: 'fb9bfabb-03d4-4205-9270-77a947fd5db3',
  },
  {
    targetType: 'CustomerResource',
    targetAmount: 1,
    budgetLimitType: BudgetLimitTypes.PreventFurtherUsage,
    currentAmount: 0,
    targetName: 'github-inc',
    alertEnabled: true,
    targetId: '1',
    pricingTargetType: BudgetPricingTargetType.ProductPricing,
    pricingTargetId: 'actions',
    uuid: '548d6177-c6d9-43d9-b437-8979386c3369',
  },
]

export const USER_CUSTOMER_BUDGETS = [
  {
    targetType: 'CustomerResource',
    targetAmount: 1,
    budgetLimitType: BudgetLimitTypes.PreventFurtherUsage,
    currentAmount: 0,
    targetName: 'test-user',
    alertEnabled: true,
    targetId: '11',
    pricingTargetType: BudgetPricingTargetType.ProductPricing,
    pricingTargetId: 'actions',
    uuid: 'fb9bfabb-03d4-4205-9270-77a947fd5db3',
  },
  {
    targetType: 'CustomerResource',
    targetAmount: 1,
    budgetLimitType: BudgetLimitTypes.PreventFurtherUsage,
    currentAmount: 0,
    targetName: 'test-user',
    alertEnabled: true,
    targetId: '1',
    pricingTargetType: BudgetPricingTargetType.ProductPricing,
    pricingTargetId: 'packages',
    uuid: '548d6177-c6d9-43d9-b437-8979386c3369',
  },
]

export const getBudgetsPagePayload = (): BudgetsPagePayload => {
  return {
    customer: USER_CUSTOMER,
    budgets: USER_CUSTOMER_BUDGETS,
    adminRoles: [],
    enabledProducts: [{friendlyProductName: 'Actions,', name: 'actions', zuoraUsageIdentifier: 'actions123'}],
    enabledSkus: [
      {
        friendlyName: 'Actions Linux,',
        sku: 'actions_linux',
        product: '',
        price: 0,
        meterType: 'Default',
        azureMeterId: '',
        freeForPublicRepos: false,
        unitType: 'Unknown',
        effectiveAt: 0,
      },
    ],
    helpUrl: 'https://helpme.github.com',
    type: '',
    copilotIapSubscription: false,
  }
}
