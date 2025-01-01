import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import UsageSubTable from '../../../components/usage/UsageTable/UsageSubTable'
import {LICENSE_SKU_MOCK_USAGE, MOCK_LINE_ITEMS} from '../../../test-utils/mock-data'
import {formatMoneyDisplay} from '../../../utils'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'

jest.mock('@github-ui/react-core/use-app-payload')
const mockedUseAppPayload = jest.mocked(useAppPayload)

function mockFeatureFlags(enabledFeatureFlags: {[key: string]: boolean | undefined}) {
  mockedUseAppPayload.mockReturnValue({
    initial_view_content: {},
    enabled_features: enabledFeatureFlags || {},
  })
}

describe('UsageSubTable', () => {
  it('renders the table headers correctly', () => {
    render(<UsageSubTable data={MOCK_LINE_ITEMS} />)
    expect(screen.getByText('SKU')).toBeInTheDocument()
    expect(screen.getByText('Units')).toBeInTheDocument()
    expect(screen.getByText('Price/unit')).toBeInTheDocument()
    expect(screen.getByText('Gross amount')).toBeInTheDocument()
    expect(screen.getByText('Billed amount')).toBeInTheDocument()
  })

  it('renders the correct number of rows', () => {
    render(<UsageSubTable data={MOCK_LINE_ITEMS} />)
    expect(screen.getAllByTestId('sub-sku-td')).toHaveLength(MOCK_LINE_ITEMS.length)
  })

  it('renders the correct data in the rows', () => {
    render(<UsageSubTable data={MOCK_LINE_ITEMS} />)

    const skuCells = screen.getAllByTestId('sub-sku-td')
    const quantityCells = screen.getAllByTestId('sub-quantity-td')
    const costPerQuantityCells = screen.getAllByTestId('sub-applied-cost-per-quantity-td')
    const grossAmountCells = screen.getAllByTestId('sub-gross-amount-td')
    const billedAmountCells = screen.getAllByTestId('sub-billed-amount-td')

    let index = 0
    for (const row of MOCK_LINE_ITEMS) {
      expect(skuCells[index]).toHaveTextContent(row.friendlySkuName)
      expect(quantityCells[index]).toHaveTextContent(row.quantity.toString())
      expect(costPerQuantityCells[index]).toHaveTextContent(formatMoneyDisplay(row.appliedCostPerQuantity, 6))
      expect(grossAmountCells[index]).toHaveTextContent(formatMoneyDisplay(row.totalAmount ?? 0))
      expect(billedAmountCells[index]).toHaveTextContent(formatMoneyDisplay(row.billedAmount))
      index++
    }
  })
})

describe('UsageSubTable with usage for licensed skus with daily emissions', () => {
  it('renders the correct data in the rows when the flag is enabled', () => {
    mockFeatureFlags({billing_proration_for_licensed_products: true})

    render(<UsageSubTable data={LICENSE_SKU_MOCK_USAGE} />)
    const skuCells = screen.getAllByTestId('sub-sku-td')
    const quantityCells = screen.getAllByTestId('sub-quantity-td')
    const costPerQuantityCells = screen.getAllByTestId('sub-applied-cost-per-quantity-td')
    const grossAmountCells = screen.getAllByTestId('sub-gross-amount-td')
    const billedAmountCells = screen.getAllByTestId('sub-billed-amount-td')

    expect(skuCells[0]).toHaveTextContent('Copilot Enterprise')
    expect(quantityCells[0]).toHaveTextContent('5 licenses')
    expect(costPerQuantityCells[0]).toHaveTextContent('$1.258065')
    expect(grossAmountCells[0]).toHaveTextContent('$6.29')
    expect(billedAmountCells[0]).toHaveTextContent('$6.29')
  })

  it('renders the correct data in the rows then the flag is disabled', () => {
    mockFeatureFlags({billing_proration_for_licensed_products: false})

    render(<UsageSubTable data={LICENSE_SKU_MOCK_USAGE} />)
    const skuCells = screen.getAllByTestId('sub-sku-td')
    const quantityCells = screen.getAllByTestId('sub-quantity-td')
    const costPerQuantityCells = screen.getAllByTestId('sub-applied-cost-per-quantity-td')
    const grossAmountCells = screen.getAllByTestId('sub-gross-amount-td')
    const billedAmountCells = screen.getAllByTestId('sub-billed-amount-td')

    expect(skuCells[0]).toHaveTextContent('Copilot Enterprise')
    expect(quantityCells[0]).toHaveTextContent('0.16 license-month')
    expect(costPerQuantityCells[0]).toHaveTextContent('$39')
    expect(grossAmountCells[0]).toHaveTextContent('$6.29')
    expect(billedAmountCells[0]).toHaveTextContent('$6.29')
  })
})
