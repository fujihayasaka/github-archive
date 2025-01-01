import {
  BUDGET_SCOPE_COST_CENTER,
  BUDGET_SCOPE_ENTERPRISE,
  BUDGET_SCOPE_ORGANIZATION,
  BUDGET_SCOPE_REPOSITORY,
} from '../constants'

export const BudgetType = {
  COST_CENTER: BUDGET_SCOPE_COST_CENTER,
  ENTERPRISE: BUDGET_SCOPE_ENTERPRISE,
  ORG: BUDGET_SCOPE_ORGANIZATION,
  REPO: BUDGET_SCOPE_REPOSITORY,
} as const

export type BudgetType = (typeof BudgetType)[keyof typeof BudgetType]

export const BudgetLimitTypes = {
  AlertingOnly: 'AlertingOnly',
  PreventFurtherUsage: 'PreventFurtherUsage',
} as const

export type BudgetLimitTypes = (typeof BudgetLimitTypes)[keyof typeof BudgetLimitTypes]
