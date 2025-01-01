import {render} from '@github-ui/react-core/test-utils'
import {noop} from '@github-ui/noop'
import {screen} from '@testing-library/react'
import {createMockEnvironment} from 'relay-test-utils'

import {BudgetScopeSelector} from '../../components/budget/BudgetScopeSelector'
import {BUDGET_SCOPE_CUSTOMER} from '../../constants'
import {RelayEnvironmentProvider} from 'react-relay'
import {PageContext} from '../../App'

type TestComponentProps = {
  environment: ReturnType<typeof createMockEnvironment>
  budgetProduct: string
  budgetScope: string
}

function TestComponent({environment, budgetProduct, budgetScope}: TestComponentProps) {
  return (
    <RelayEnvironmentProvider environment={environment}>
      <BudgetScopeSelector
        budgetScope={budgetScope}
        budgetScopeIds={['1']}
        setBudgetScope={noop}
        setBudgetScopeId={noop}
        slug=""
        budgetProduct={budgetProduct}
      />
    </RelayEnvironmentProvider>
  )
}

test('Displays correct scope for an enterprise when a non-high watermark product is selected', () => {
  const environment = createMockEnvironment()
  render(
    <PageContext.Provider
      value={{isStafftoolsRoute: false, isEnterpriseRoute: true, isOrganizationRoute: false, isUserRoute: false}}
    >
      <TestComponent environment={environment} budgetProduct="actions" budgetScope={BUDGET_SCOPE_CUSTOMER} />
    </PageContext.Provider>,
  )

  expect(screen.getByRole('heading')).toHaveTextContent('Budget scope')
  expect(screen.getByRole('group')).toHaveTextContent('Enterprise')
  expect(screen.getByRole('group')).toHaveTextContent('Organization')
  expect(screen.getByRole('group')).toHaveTextContent('Repository')
})

test('Displays correct scopes for an enterprise for when a high-watermark product is selected', () => {
  const environment = createMockEnvironment()
  render(
    <PageContext.Provider
      value={{isStafftoolsRoute: false, isEnterpriseRoute: true, isOrganizationRoute: false, isUserRoute: false}}
    >
      <TestComponent environment={environment} budgetProduct="copilot" budgetScope={BUDGET_SCOPE_CUSTOMER} />
    </PageContext.Provider>,
  )

  expect(screen.getByRole('group')).toHaveTextContent('Enterprise')
  expect(screen.getByRole('group')).toHaveTextContent('Cost center')
})

test('Displays correct scopes for an organization for when a high-watermark product is selected', () => {
  const environment = createMockEnvironment()
  render(
    <PageContext.Provider
      value={{isStafftoolsRoute: false, isEnterpriseRoute: false, isOrganizationRoute: true, isUserRoute: false}}
    >
      <TestComponent environment={environment} budgetProduct="copilot" budgetScope={BUDGET_SCOPE_CUSTOMER} />
    </PageContext.Provider>,
  )

  expect(screen.getByRole('group')).toHaveTextContent('Organization')
})

test('Displays correct scopes for a user for when a high-watermark product is selected', () => {
  const environment = createMockEnvironment()
  render(
    <PageContext.Provider
      value={{isStafftoolsRoute: false, isEnterpriseRoute: false, isOrganizationRoute: false, isUserRoute: true}}
    >
      <TestComponent environment={environment} budgetProduct="copilot" budgetScope={BUDGET_SCOPE_CUSTOMER} />
    </PageContext.Provider>,
  )

  expect(screen.getByRole('group')).toHaveTextContent('Account')
})

test('Displays correct scopes for a user for when copilot_premium_request is selected', () => {
  const environment = createMockEnvironment()
  render(
    <PageContext.Provider
      value={{isStafftoolsRoute: false, isEnterpriseRoute: false, isOrganizationRoute: false, isUserRoute: true}}
    >
      <TestComponent
        environment={environment}
        budgetProduct="copilot_premium_request"
        budgetScope={BUDGET_SCOPE_CUSTOMER}
      />
    </PageContext.Provider>,
  )

  expect(screen.getByRole('group')).toHaveTextContent('Account')
  expect(screen.getByRole('group')).not.toHaveTextContent('Repository')
})
