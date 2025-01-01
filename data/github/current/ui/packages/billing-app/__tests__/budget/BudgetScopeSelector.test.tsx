import {render} from '@github-ui/react-core/test-utils'
import {noop} from '@github-ui/noop'
import {screen} from '@testing-library/react'
import {createMockEnvironment} from 'relay-test-utils'

import {BudgetScopeSelector} from '../../components/budget/BudgetScopeSelector'
import {BUDGET_SCOPE_ENTERPRISE} from '../../constants'
import {RelayEnvironmentProvider} from 'react-relay'
import {mockClientEnv} from '@github-ui/client-env/mock'

type TestComponentProps = {
  environment: ReturnType<typeof createMockEnvironment>
}

function TestComponent({environment}: TestComponentProps) {
  mockClientEnv({
    featureFlags: ['use_paginated_organization_picker'],
  })

  return (
    <RelayEnvironmentProvider environment={environment}>
      <BudgetScopeSelector
        budgetScope={BUDGET_SCOPE_ENTERPRISE}
        budgetScopeIds={['1']}
        setBudgetScope={noop}
        setBudgetScopeId={noop}
        slug=""
        budgetProduct="actions"
      />
    </RelayEnvironmentProvider>
  )
}

test('Renders', () => {
  const environment = createMockEnvironment()
  render(<TestComponent environment={environment} />)

  expect(screen.getByRole('heading')).toHaveTextContent('Budget scope')
  expect(screen.getByRole('group')).toHaveTextContent('Enterprise')
  expect(screen.getByRole('group')).toHaveTextContent('Organization')
  expect(screen.getByRole('group')).toHaveTextContent('Repository')
})
