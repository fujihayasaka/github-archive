import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {BudgetSelectedScope} from '../../components/budget/BudgetSelectedScope'
import {BUDGET_SCOPE_CUSTOMER} from '../../constants'
import {PageContext} from '../../App'

type PageContextValue = {
  isEnterpriseRoute: boolean
  isOrganizationRoute: boolean
  isUserRoute: boolean
  isStafftoolsRoute: boolean
}

const renderWithContext = (ui: React.ReactElement, contextValue: PageContextValue) => {
  return render(<PageContext.Provider value={contextValue}>{ui}</PageContext.Provider>)
}

test('Renders the component for an enterprise account', () => {
  render(<BudgetSelectedScope budgetScope={BUDGET_SCOPE_CUSTOMER} budgetTargetName="github-inc" />)
  expect(screen.getByRole('heading')).toHaveTextContent('Budget scope')
  expect(screen.getByText('Enterprise')).toBeInTheDocument()
  expect(screen.getByText('Spending for all organizations and repositories in your enterprise')).toBeInTheDocument()
  // This disable is needed because the icon has an aria-hidden attribute and those elements are ignored by testing-library
  // eslint-disable-next-line testing-library/no-node-access
  const globeIcon = document.querySelector('.octicon-globe')
  expect(globeIcon).toBeInTheDocument()
  expect(screen.getByText('github-inc')).toBeInTheDocument()
})

test('Renders with the correctly labeled scope for an individual user account', () => {
  const mockContextValue: PageContextValue = {
    isEnterpriseRoute: false,
    isOrganizationRoute: false,
    isUserRoute: true,
    isStafftoolsRoute: false,
  }
  renderWithContext(
    <BudgetSelectedScope budgetScope={BUDGET_SCOPE_CUSTOMER} budgetTargetName="github-inc" />,
    mockContextValue,
  )
  expect(screen.getByRole('heading')).toHaveTextContent('Budget scope')
  expect(screen.getByText('Account')).toBeInTheDocument()
  expect(screen.getByText('Spending for all repositories owned by your account')).toBeInTheDocument()
})

test('Renders with the correctly labeled scope for an organization account', () => {
  const mockContextValue: PageContextValue = {
    isEnterpriseRoute: false,
    isOrganizationRoute: true,
    isUserRoute: false,
    isStafftoolsRoute: false,
  }
  renderWithContext(
    <BudgetSelectedScope budgetScope={BUDGET_SCOPE_CUSTOMER} budgetTargetName="github-inc" />,
    mockContextValue,
  )
  expect(screen.getByRole('heading')).toHaveTextContent('Budget scope')
  expect(screen.getByText('Organization')).toBeInTheDocument()
  expect(screen.getByText('Spending for all repositories in your organization')).toBeInTheDocument()
})
