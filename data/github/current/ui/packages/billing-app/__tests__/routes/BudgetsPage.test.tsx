import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {PageContext} from '../../App'
import {BudgetsPage} from '../../routes/BudgetsPage'
import {getBudgetsPagePayload, USER_CUSTOMER_BUDGETS} from '../../test-utils/mock-data'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import useBudgetsPage from '../../hooks/budget/use-budgets-page'
import useFilteredBudgets from '../../hooks/budget/use-filtered-budgets'
import {RequestState} from '../../enums'
import type {Budget} from '../../types/budgets'

type PageContextType = {
  isStafftoolsRoute: boolean
  isOrganizationRoute: boolean
  isEnterpriseRoute: boolean
  isUserRoute: boolean
}

jest.mock('@github-ui/react-core/use-route-payload')
jest.mock('../../hooks/budget/use-budgets-page')
jest.mock('../../hooks/budget/use-filtered-budgets')

const mockBudgetsPagePayload = getBudgetsPagePayload()

const mockUseRoutePayload = useRoutePayload as jest.Mock
const mockUseBudgetsPage = useBudgetsPage as jest.Mock
const mockUseFilteredBudgets = useFilteredBudgets as jest.Mock

mockUseRoutePayload.mockReturnValue(mockBudgetsPagePayload)

const renderBudgetsPage = (contextValue: PageContextType, budgets: Budget[]) => {
  mockUseBudgetsPage.mockReturnValue({
    budgets,
    deleteBudgetFromPage: jest.fn(),
    requestState: RequestState.IDLE,
  })

  mockUseFilteredBudgets.mockReturnValue({
    customerBudgets: budgets,
    nonCustomerBudgets: [],
  })

  render(
    <PageContext.Provider value={contextValue}>
      <BudgetsPage />
    </PageContext.Provider>,
    {routePayload: mockBudgetsPagePayload},
  )
}

const defaultContextValue: PageContextType = {
  isStafftoolsRoute: false,
  isOrganizationRoute: false,
  isEnterpriseRoute: false,
  isUserRoute: true,
}

test('Shows the customer budget table with the correct title for an individual user account', async () => {
  renderBudgetsPage(defaultContextValue, USER_CUSTOMER_BUDGETS)
  expect(await screen.findByText(/Account budgets/)).toBeInTheDocument()
})

test('Shows the correct text for an individual user account when the user has not set up any budgets yet', async () => {
  renderBudgetsPage(defaultContextValue, [])
  expect(
    await screen.findByText(/Create budgets to track your spending on products like Actions and Copilot/),
  ).toBeInTheDocument()
})

test('Shows the correct text for an org account that has not set up any budgets yet', async () => {
  renderBudgetsPage({...defaultContextValue, isUserRoute: false, isOrganizationRoute: true}, [])
  expect(
    await screen.findByText(
      /Create budgets to track your spending on products like Actions and Copilot for a single repository or the entire organization./,
    ),
  ).toBeInTheDocument()
})

test('Shows the correct text for an enterprise account that has not set up any budgets yet', async () => {
  renderBudgetsPage({...defaultContextValue, isUserRoute: false, isEnterpriseRoute: true}, [])
  expect(
    await screen.findByText(
      /Create budgets to track your spending on products like Actions and Copilot for a single repository or the entire organization./,
    ),
  ).toBeInTheDocument()
})
