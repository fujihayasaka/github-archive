import {useMemo} from 'react'
import {BUDGET_SCOPE_CUSTOMER, BUDGET_SCOPE_ENTERPRISE} from '../../constants'
import type {Budget} from '../../types/budgets'

const useFilteredBudgets = (budgets: Budget[], isOrganizationRoute: boolean, isUserRoute: boolean) => {
  return useMemo(() => {
    let customerBudgets: Budget[]
    let nonCustomerBudgets: Budget[]

    if (isOrganizationRoute || isUserRoute) {
      customerBudgets = budgets
        .filter(b => b.targetType === BUDGET_SCOPE_CUSTOMER) // TODO: remove 'Enterprise' after data migration
        .sort((a, b) => (a.targetName > b.targetName ? 1 : -1))
      nonCustomerBudgets = budgets
        .filter(b => b.targetType !== BUDGET_SCOPE_ENTERPRISE && b.targetType !== BUDGET_SCOPE_CUSTOMER) // TODO: remove 'Enterprise' after data migration
        .sort((a, b) => (a.targetName > b.targetName ? 1 : -1))
    } else {
      customerBudgets = budgets
        .filter(b => b.targetType === BUDGET_SCOPE_CUSTOMER || b.targetType === BUDGET_SCOPE_ENTERPRISE) // TODO: remove 'Enterprise' after data migration
        .sort((a, b) => (a.targetName > b.targetName ? 1 : -1))
      nonCustomerBudgets = budgets
        .filter(b => b.targetType !== BUDGET_SCOPE_CUSTOMER && b.targetType !== BUDGET_SCOPE_ENTERPRISE) // TODO: remove 'Enterprise' after data migration
        .sort((a, b) => (a.targetName > b.targetName ? 1 : -1))
    }

    return {customerBudgets, nonCustomerBudgets}
  }, [budgets, isOrganizationRoute, isUserRoute])
}

export default useFilteredBudgets
