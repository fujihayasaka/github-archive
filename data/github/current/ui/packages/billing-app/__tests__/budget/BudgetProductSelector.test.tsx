import {render} from '@github-ui/react-core/test-utils'
import {screen, fireEvent, within} from '@testing-library/react'

import {BudgetProductSelector} from '../../components/budget/BudgetProductSelector'

import {MOCK_PRODUCTS, MOCK_SKUS_PRICING} from '../../test-utils/mock-data'
import {mockClientEnv} from '@github-ui/client-env/mock'

const mockSetSkuFilter = jest.fn().mockName('setSkuFilter')

describe('BudgetProductSelector', () => {
  it('only renders product-level budget options when skuLevelBudgets is disabled', () => {
    render(
      <BudgetProductSelector
        products={MOCK_PRODUCTS}
        skus={MOCK_SKUS_PRICING}
        budgetType="ProductPricing"
        budgetValue=""
        setBudgetType={jest.fn()}
        setBudgetValue={jest.fn()}
        isUserRoute={false}
        showSkuError={false}
        skuFilter={''}
        setSkuFilter={mockSetSkuFilter}
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )

    expect(screen.getByText('Product')).toBeInTheDocument()
    for (const product of MOCK_PRODUCTS) {
      expect(screen.getByLabelText(product.friendlyProductName)).toBeInTheDocument()
    }

    expect(screen.queryByText('SKU')).not.toBeInTheDocument()
  })

  it('renders SKU-level budget options when skuLevelBudgets is enabled', () => {
    mockClientEnv({
      featureFlags: ['billing_sku_level_budgets'],
    })

    render(
      <BudgetProductSelector
        products={MOCK_PRODUCTS}
        skus={MOCK_SKUS_PRICING}
        budgetType="SkuPricing"
        budgetValue=""
        setBudgetType={jest.fn()}
        setBudgetValue={jest.fn()}
        isUserRoute={false}
        showSkuError={false}
        skuFilter={''}
        setSkuFilter={mockSetSkuFilter}
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )

    expect(screen.getByText('Budget type')).toBeInTheDocument()
    expect(screen.getByText('Product-level budget')).toBeInTheDocument()
    expect(screen.getByText('SKU-level budget')).toBeInTheDocument()
  })

  it('disables Copilot product for subscription plans when isUserRoute is true', () => {
    render(
      <BudgetProductSelector
        products={MOCK_PRODUCTS}
        skus={MOCK_SKUS_PRICING}
        budgetType="ProductPricing"
        budgetValue=""
        setBudgetType={jest.fn()}
        setBudgetValue={jest.fn()}
        isUserRoute
        showSkuError={false}
        skuFilter={''}
        setSkuFilter={mockSetSkuFilter}
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )

    const copilotRadio = screen.getByLabelText('Copilot')
    expect(copilotRadio).toBeDisabled()
    expect(screen.getByText('Not available for subscription plans')).toBeInTheDocument()
  })

  it('filters SKUs correctly based on the selected product', async () => {
    mockClientEnv({
      featureFlags: ['billing_sku_level_budgets'],
    })

    const {user} = render(
      <BudgetProductSelector
        products={MOCK_PRODUCTS}
        skus={MOCK_SKUS_PRICING}
        budgetType="SkuPricing"
        budgetValue=""
        setBudgetType={jest.fn()}
        setBudgetValue={jest.fn()}
        isUserRoute={false}
        showSkuError={false}
        skuFilter={'Copilot'}
        setSkuFilter={mockSetSkuFilter}
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )

    // Select the SKU-level budget radio button
    await user.click(screen.getByDisplayValue('SkuPricing'))

    // Open the Product dropdown
    await user.click(screen.getByText('Actions'))

    // Select the "Copilot" option from the dropdown
    await user.click(screen.getByText('Copilot'))

    await user.click(screen.getByText('Select SKU'))

    // Verify that the first SKU displayed is "Copilot SKU"
    const skuItems = within(screen.getByRole('listbox')).getAllByRole('option')
    expect(skuItems[0]).toHaveTextContent('Copilot SKU')
    // Verify that the length of SKU items is 1
    expect(skuItems).toHaveLength(1)
  })

  it('excludes Copilot Premium Request SKU', () => {
    mockClientEnv({
      featureFlags: ['billing_sku_level_budgets'],
    })

    render(
      <BudgetProductSelector
        products={MOCK_PRODUCTS}
        skus={MOCK_SKUS_PRICING}
        budgetType="ProductPricing"
        budgetValue=""
        setBudgetType={jest.fn()}
        setBudgetValue={jest.fn()}
        isUserRoute={false}
        showSkuError={false}
        skuFilter={''}
        setSkuFilter={mockSetSkuFilter}
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )

    // Open the SKU selector
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(screen.getByLabelText('SKU-level budget'))

    // Check that Copilot Premium Request SKU is not displayed
    expect(screen.queryByText('Copilot Premium Request')).not.toBeInTheDocument()
  })

  it('shows the correct first SKU when a product is selected', async () => {
    mockClientEnv({
      featureFlags: ['billing_sku_level_budgets'],
    })

    const {user} = render(
      <BudgetProductSelector
        products={MOCK_PRODUCTS}
        skus={MOCK_SKUS_PRICING}
        budgetType="SkuPricing"
        budgetValue=""
        setBudgetType={jest.fn()}
        setBudgetValue={jest.fn()}
        isUserRoute={false}
        showSkuError={false}
        skuFilter={''}
        setSkuFilter={mockSetSkuFilter}
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )

    // Select the SKU-level budget radio button
    await user.click(screen.getByDisplayValue('SkuPricing'))

    // Open the Product dropdown
    await user.click(screen.getByText('Actions'))

    // Select the "actions" product
    await user.click(screen.getByText('Select SKU'))

    // Verify that the first SKU displayed is "Github Actions"
    const skuItems = within(screen.getByRole('listbox')).getAllByRole('option')
    expect(skuItems[0]).toHaveTextContent('Actions Linux')
  })

  it('fuzzy searches SKUs by including partial text matches', async () => {
    mockClientEnv({
      featureFlags: ['billing_sku_level_budgets'],
    })

    const {user} = render(
      <BudgetProductSelector
        products={MOCK_PRODUCTS}
        skus={MOCK_SKUS_PRICING}
        budgetType="SkuPricing"
        budgetValue=""
        setBudgetType={jest.fn()}
        setBudgetValue={jest.fn()}
        isUserRoute={false}
        showSkuError={false}
        skuFilter={'Linux'}
        setSkuFilter={mockSetSkuFilter}
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )

    // Select the SKU-level budget radio button
    await user.click(screen.getByDisplayValue('SkuPricing'))

    // Open the Product dropdown and select the "Actions" product
    await user.click(screen.getByText('Actions'))

    // Open the SKU dropdown
    await user.click(screen.getByText('Select SKU'))

    // Type "Linux" in the search box (partial match in "Actions Linux")
    const searchInput = screen.getByPlaceholderText('Search')
    await user.type(searchInput, 'Linux')

    // Verify the "Actions Linux" SKU is found
    const skuItems = within(screen.getByRole('listbox')).getAllByRole('option')

    expect(skuItems.length).toBe(1)
    expect(skuItems[0]).toHaveTextContent('Actions Linux')

    // // Clear the search and try another partial search
    await user.clear(searchInput)
    await user.type(searchInput, 'nux')

    // Verify the "Actions Linux" SKU is still found with a partial match
    const skuItemsAfterPartialSearch = within(screen.getByRole('listbox')).getAllByRole('option')
    expect(skuItemsAfterPartialSearch.length).toBe(1)
    expect(skuItemsAfterPartialSearch[0]).toHaveTextContent('Actions Linux')
  })
})
