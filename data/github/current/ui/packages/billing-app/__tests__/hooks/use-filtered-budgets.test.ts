import {renderHook} from '@testing-library/react'
import useFilteredBudgets from '../../hooks/budget/use-filtered-budgets'
import {MOCK_BUDGETS_TO_FILTER} from '../../test-utils/mock-data/budgets'

describe('useFilteredBudgets', () => {
  test('filters and sorts budgets correctly for organization or user route', () => {
    const {result} = renderHook(() => useFilteredBudgets(MOCK_BUDGETS_TO_FILTER, true, false))

    expect(result.current.customerBudgets.length).toBe(2)
    expect(result.current.nonCustomerBudgets.length).toBe(1)
  })

  test('filters and sorts budgets correctly for an enterprise customer', () => {
    const {result} = renderHook(() => useFilteredBudgets(MOCK_BUDGETS_TO_FILTER, false, false))

    expect(result.current.customerBudgets.length).toBe(2)
    expect(result.current.nonCustomerBudgets.length).toBe(1)
  })
})
