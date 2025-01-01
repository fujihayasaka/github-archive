import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {BudgetSelectedProduct} from '../../components/budget/BudgetSelectedProduct'
import {MOCK_PRODUCTS, MOCK_SKUS_PRICING} from '../../test-utils/mock-data'

test('Renders the component', () => {
  render(
    <BudgetSelectedProduct budgetValue="actions" enabledSkus={MOCK_SKUS_PRICING} enabledProducts={MOCK_PRODUCTS} />,
  )
  expect(screen.getByRole('heading')).toHaveTextContent('Product')
  expect(screen.getByText('Actions')).toBeInTheDocument()
})
