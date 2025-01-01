import {
  DEFAULT_FILTERS,
  GROUP_SELECTIONS,
  LICENSE_SKU_MOCK_USAGE,
  LICENSE_SKU_ORG_DATA,
  LICENSE_SKU_USAGE_PARTIAL_MONTH,
  LICENSE_SKU_WITH_COST_CENTER_NET_USAGE,
  LICENSE_SKU_WITH_COST_CENTER_NET_USAGE_DIFFERENT_DAYS,
  MOCK_LINE_ITEMS,
  MOCK_LINE_ITEMS_COSTCENTERS,
  MOCK_ORG_LINE_ITEMS,
  MOCK_REPO_LINE_ITEMS,
  ORG_ROW_LICENSE_SKU_DATA,
  PERIOD_SELECTIONS,
} from '../../../test-utils/mock-data'
import {fireEvent, screen, waitFor, within} from '@testing-library/react'

import {RequestState, UsageGrouping} from '../../../enums'
import {UsageTable} from '../../../components/usage'
import {render} from '@github-ui/react-core/test-utils'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import useUsageTableData from '../../../hooks/usage/use-usage-table-data'

import type {NetUsageLineItem} from '../../../types/usage'

jest.mock('@github-ui/ssr-utils', () => ({
  get ssrSafeLocation() {
    return jest.fn().mockImplementation(() => {
      return {origin: 'https://github.localhost', pathname: '/enterprises/github-inc/billing'}
    })()
  },
}))

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useParams: jest.fn().mockReturnValue({business: 'github-inc'}),
}))

jest.mock('../../../hooks/usage/use-usage-table-data')
jest.mocked(useUsageTableData).mockReturnValue({
  usageTableData: MOCK_LINE_ITEMS as NetUsageLineItem[],
  requestState: RequestState.IDLE,
  otherUsage: [],
})

describe('UsageTable', () => {
  test('Renders usage by SKU when group by SKU is selected', async () => {
    render(
      <UsageTable
        filters={{...DEFAULT_FILTERS, group: GROUP_SELECTIONS[2]}}
        isEnterpriseRoute
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )

    const expectedSKUs = MOCK_LINE_ITEMS.sort((a, b) => {
      return a.friendlySkuName.localeCompare(b.friendlySkuName)
    }).map(item => item.friendlySkuName)
    const expectedBilledAmount = ['$10.10', '$2.59', '$3.00']
    const expectedQuantity = ['20 min', '10 GB-hr', '15 min']
    const expectedAppliedCostPerQuantity = ['$0.505', '$0.259', '$0.20']

    const foundSkuCells = await screen.findAllByTestId('identifier-td')
    for (const [i, sku] of expectedSKUs.entries()) {
      expect(foundSkuCells[i]).toContainElement(await screen.findByText(sku))
    }

    expect((await screen.findAllByTestId('billed-amount-td')).map(cell => cell.innerHTML)).toEqual(expectedBilledAmount)
    expect((await screen.findAllByTestId('quantity-td')).map(cell => cell.innerHTML)).toEqual(expectedQuantity)
    expect((await screen.findAllByTestId('applied-cost-per-quantity-td')).map(cell => cell.innerHTML)).toEqual(
      expectedAppliedCostPerQuantity,
    )
  })

  test('Renders usage by product when group by product is selected', async () => {
    const {user} = render(
      <UsageTable
        filters={{...DEFAULT_FILTERS, group: GROUP_SELECTIONS[1]}}
        isEnterpriseRoute
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )

    const expectedProducts = ['Packages', 'Actions']
    const expectedBilledAmount = ['$2.59', '$13.10']

    for (const product of expectedProducts) {
      const productCell = await screen.findByText(product)
      expect(productCell).toBeInTheDocument()
    }

    expect((await screen.findAllByTestId('billed-amount-td')).map(cell => cell.innerHTML)).toEqual(
      expect.arrayContaining(expectedBilledAmount),
    )

    // expand sub table
    await user.click(within(screen.getByTestId('usage-actions')).getByTestId('usage-details'))

    await waitFor(() => {
      expect(within(screen.getByTestId('usage-actions')).getByTestId('usage-sub-table')).toBeVisible()
    })

    const expectedSubSKUs = ['Macos 12-core', 'Windows 4-core']
    const expectedSubBilledAmount = ['$10.10', '$3.00']
    const expectedSubQuantity = ['20 min', '15 min']
    const expectedSubAppliedCostPerQuantity = ['$0.505', '$0.20']

    const foundSkuCells = await screen.findAllByTestId('sub-sku-td')
    for (const [i, sku] of expectedSubSKUs.entries()) {
      expect(foundSkuCells[i]).toContainElement(await screen.findByText(sku))
    }

    expect((await screen.findAllByTestId('sub-billed-amount-td')).map(cell => cell.innerHTML)).toEqual(
      expectedSubBilledAmount,
    )
    expect((await screen.findAllByTestId('sub-quantity-td')).map(cell => cell.innerHTML)).toEqual(expectedSubQuantity)
    expect((await screen.findAllByTestId('sub-applied-cost-per-quantity-td')).map(cell => cell.innerHTML)).toEqual(
      expectedSubAppliedCostPerQuantity,
    )

    // close sub table
    await user.click(within(screen.getByTestId('usage-actions')).getByTestId('usage-details'))
    await waitFor(() => {
      expect(screen.queryByTestId('usage-sub-table')).toBeNull()
    })
  })

  test('Renders usage when group by cost center is selected', async () => {
    jest.mocked(useUsageTableData).mockReturnValue({
      usageTableData: MOCK_LINE_ITEMS_COSTCENTERS as NetUsageLineItem[],
      requestState: RequestState.IDLE,
      otherUsage: [],
    })
    render(
      <UsageTable
        filters={{...DEFAULT_FILTERS, group: GROUP_SELECTIONS[5]}}
        isEnterpriseRoute
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )

    const expectedEntities = ['test', 'cost-center-test']
    const expectedBilledAmount = ['$2.59', '$13.10']

    const foundProductCells = await screen.findAllByTestId('identifier-td')
    for (const [i, entity] of expectedEntities.entries()) {
      expect(foundProductCells[i]).toContainElement(await screen.findByText(entity))
    }
    expect((await screen.findAllByTestId('billed-amount-td')).map(cell => cell.innerHTML)).toEqual(expectedBilledAmount)
  })

  describe('when group by none is selected', () => {
    test('Renders usage by month when current year is selected', async () => {
      const {user} = render(
        <UsageTable
          filters={{...DEFAULT_FILTERS, period: PERIOD_SELECTIONS[2]}}
          isEnterpriseRoute
          codingAgentEnabled={false}
          sparkEnabled={false}
        />,
      )
      const foundDateCells = await screen.findAllByTestId('identifier-td')
      const expectedDates = ['Mar 2023', 'Apr 2023', 'May 2023']
      const expectedBilledAmount = ['$2.59', '$3.00', '$10.10']

      for (const [i, date] of expectedDates.entries()) {
        expect(foundDateCells[i]).toContainElement(await screen.findByText(date))
      }

      expect((await screen.findAllByTestId('billed-amount-td')).map(cell => cell.innerHTML)).toEqual(
        expectedBilledAmount,
      )
      // expand sub table
      await user.click(within(screen.getByTestId('usage-date-Mar 2023')).getByTestId('usage-details'))
      await waitFor(() => {
        expect(within(screen.getByTestId('usage-date-Mar 2023')).getByTestId('usage-sub-table')).toBeVisible()
      })

      const expectedSubSKUs = ['Shared Storage']
      const expectedSubBilledAmount = ['$2.59']
      const expectedSubQuantity = ['10 GB-hr']
      const expectedSubAppliedCostPerQuantity = ['$0.259']
      const subTable = within(screen.getByTestId('usage-date-Mar 2023')).getByTestId('usage-sub-table')
      const foundSkuCells = await within(subTable).findAllByTestId('sub-sku-td')
      for (const [i, sku] of expectedSubSKUs.entries()) {
        expect(foundSkuCells[i]).toContainElement(await screen.findByText(sku))
      }

      expect((await within(subTable).findAllByTestId('sub-billed-amount-td')).map(cell => cell.innerHTML)).toEqual(
        expectedSubBilledAmount,
      )
      expect((await within(subTable).findAllByTestId('sub-quantity-td')).map(cell => cell.innerHTML)).toEqual(
        expectedSubQuantity,
      )
      expect(
        (await within(subTable).findAllByTestId('sub-applied-cost-per-quantity-td')).map(cell => cell.innerHTML),
      ).toEqual(expectedSubAppliedCostPerQuantity)
      await user.click(within(screen.getByTestId('usage-date-Mar 2023')).getByTestId('usage-details'))
      await waitFor(() => {
        expect(screen.queryByTestId('usage-sub-table')).toBeNull()
      })
    })

    test('Renders usage by month when last year is selected', async () => {
      const {user} = render(
        <UsageTable
          filters={{...DEFAULT_FILTERS, period: PERIOD_SELECTIONS[4]}}
          isEnterpriseRoute
          codingAgentEnabled={false}
          sparkEnabled={false}
        />,
      )
      const foundDateCells = await screen.findAllByTestId('identifier-td')
      const expectedDates = ['Mar 2023', 'Apr 2023', 'May 2023']
      const expectedBilledAmount = ['$2.59', '$3.00', '$10.10']

      for (const [i, date] of expectedDates.entries()) {
        expect(foundDateCells[i]).toContainElement(await screen.findByText(date))
      }

      expect((await screen.findAllByTestId('billed-amount-td')).map(cell => cell.innerHTML)).toEqual(
        expectedBilledAmount,
      )
      // expand sub table
      await user.click(within(screen.getByTestId('usage-date-Mar 2023')).getByTestId('usage-details'))
      await waitFor(() => {
        expect(within(screen.getByTestId('usage-date-Mar 2023')).getByTestId('usage-sub-table')).toBeVisible()
      })

      const expectedSubSKUs = ['Shared Storage']
      const expectedSubBilledAmount = ['$2.59']
      const expectedSubQuantity = ['10 GB-hr']
      const expectedSubAppliedCostPerQuantity = ['$0.259']
      const subTable = within(screen.getByTestId('usage-date-Mar 2023')).getByTestId('usage-sub-table')
      const foundSkuCells = await within(subTable).findAllByTestId('sub-sku-td')
      for (const [i, sku] of expectedSubSKUs.entries()) {
        expect(foundSkuCells[i]).toContainElement(await screen.findByText(sku))
      }

      expect((await within(subTable).findAllByTestId('sub-billed-amount-td')).map(cell => cell.innerHTML)).toEqual(
        expectedSubBilledAmount,
      )
      expect((await within(subTable).findAllByTestId('sub-quantity-td')).map(cell => cell.innerHTML)).toEqual(
        expectedSubQuantity,
      )
      expect(
        (await within(subTable).findAllByTestId('sub-applied-cost-per-quantity-td')).map(cell => cell.innerHTML),
      ).toEqual(expectedSubAppliedCostPerQuantity)
      await user.click(within(screen.getByTestId('usage-date-Mar 2023')).getByTestId('usage-details'))
      await waitFor(() => {
        expect(screen.queryByTestId('usage-sub-table')).toBeNull()
      })
    })
  })

  test('Renders usage with day precision when current month is selected', async () => {
    render(
      <UsageTable
        filters={{...DEFAULT_FILTERS, period: PERIOD_SELECTIONS[1]}}
        isEnterpriseRoute
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )
    const foundDateCells = await screen.findAllByTestId('identifier-td')
    const expectedDates = ['Mar 1, 2023', 'Apr 2, 2023', 'May 3, 2023']
    const expectedBilledAmount = ['$2.59', '$3.00', '$10.10']

    for (const [i, date] of expectedDates.entries()) {
      expect(foundDateCells[i]).toContainElement(await screen.findByText(date))
    }

    expect((await screen.findAllByTestId('billed-amount-td')).map(cell => cell.innerHTML)).toEqual(expectedBilledAmount)
  })

  test('Renders usage with day precision when last month is selected', async () => {
    render(
      <UsageTable
        filters={{...DEFAULT_FILTERS, period: PERIOD_SELECTIONS[3]}}
        isEnterpriseRoute
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )
    const foundDateCells = await screen.findAllByTestId('identifier-td')
    const expectedDates = ['Mar 1, 2023', 'Apr 2, 2023', 'May 3, 2023']
    const expectedBilledAmount = ['$2.59', '$3.00', '$10.10']

    for (const [i, date] of expectedDates.entries()) {
      expect(foundDateCells[i]).toContainElement(await screen.findByText(date))
    }

    expect((await screen.findAllByTestId('billed-amount-td')).map(cell => cell.innerHTML)).toEqual(expectedBilledAmount)
  })

  test('Renders usage with hour precision when current day is selected', async () => {
    render(
      <UsageTable
        filters={{...DEFAULT_FILTERS, period: PERIOD_SELECTIONS[0]}}
        isEnterpriseRoute
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )
    const foundDateCells = await screen.findAllByTestId('identifier-td')
    const expectedDates = ['8 AM', '9 AM', '10 AM']
    const expectedBilledAmount = ['$2.59', '$3.00', '$10.10']

    for (const [i, date] of expectedDates.entries()) {
      expect(foundDateCells[i]).toContainElement(await screen.findByText(date))
    }

    expect((await screen.findAllByTestId('billed-amount-td')).map(cell => cell.innerHTML)).toEqual(expectedBilledAmount)
  })
})

describe('UsageTable when grouping by org or repo', () => {
  test('Renders usage by organization when group by organization is selected', async () => {
    jest.mocked(useUsageTableData).mockReturnValue({
      // @ts-expect-error - the returned response of repo usage line items does not directly map to a net usage line item
      usageTableData: MOCK_REPO_LINE_ITEMS,
      requestState: RequestState.IDLE,
      otherUsage: [],
    })

    const {user} = render(
      <UsageTable
        filters={{...DEFAULT_FILTERS, group: GROUP_SELECTIONS[3]}}
        isEnterpriseRoute
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )
    const expectedOrgs = ['test-org-b', 'test-org-c', 'test-org-a', 'test-org-d', 'test-org-e', 'test-org-f']
    const expectedBilledAmount = ['$6.00', '$4.00', '$3.60', '$2.00', '$2.00', '$2.00']

    const foundOrgCells = await screen.findAllByTestId('identifier-td')
    for (const [i, org] of expectedOrgs.entries()) {
      expect(foundOrgCells[i]).toContainElement(await screen.findByText(org))
    }
    expect((await screen.findAllByTestId('gross-amount-td')).map(cell => cell.innerHTML)).toEqual(expectedBilledAmount)

    expect((await screen.findAllByTestId('billed-amount-td')).map(cell => cell.innerHTML)).toEqual([
      '$6.00',
      '$4.00',
      '$3.60',
      '$2.00',
      '$2.00',
      '$2.00',
    ])

    // mock the request we make when the sub table row is expanded for an org
    mockFetch.mockRouteOnce(
      `/enterprises/github-inc/billing/net_usage?customer_id=${DEFAULT_FILTERS.customer.id}&group=${UsageGrouping.SKU}&period=${DEFAULT_FILTERS.period?.type}&query=org%3Atest-org-a`,
      {usage: [{...MOCK_ORG_LINE_ITEMS[0], grossAmount: 2}]},
    )

    // expand sub table row for org a's usage
    await user.click(within(screen.getByTestId('usage-test-org-a')).getByTestId('usage-details'))

    await waitFor(() => {
      expect(within(screen.getByTestId('usage-test-org-a')).getByTestId('usage-sub-table')).toBeVisible()
    })
    const expectedSubSKU = 'Actions Linux'
    const expectedSubGrossAmount = '$2.00'
    const expectedSubQuantity = '10 min'
    const expectedSubAppliedCostPerQuantity = '$0.20'

    const skuCell = await screen.findByTestId('sub-sku-td')
    expect(skuCell).toContainElement(await screen.findByText(expectedSubSKU))

    const grossAmount = await screen.findByTestId('sub-gross-amount-td')
    expect(grossAmount.innerHTML).toEqual(expectedSubGrossAmount)

    // We do not show billed amount (net) for org/repo groupings
    const billedAmount = await screen.findByTestId('sub-billed-amount-td')
    expect(billedAmount.innerHTML).toEqual('N/A')

    const quantity = await screen.findByTestId('sub-quantity-td')
    expect(quantity.innerHTML).toEqual(expectedSubQuantity)

    const unitPrice = await screen.findByTestId('sub-applied-cost-per-quantity-td')
    expect(unitPrice.innerHTML).toEqual(expectedSubAppliedCostPerQuantity)

    // close sub table
    await user.click(within(screen.getByTestId('usage-test-org-a')).getByTestId('usage-details'))
    await waitFor(() => {
      expect(screen.queryByTestId('usage-sub-table')).toBeNull()
    })
  })

  test('Renders usage by repo when group by repo is selected', async () => {
    jest.mocked(useUsageTableData).mockReturnValue({
      // @ts-expect-error - the returned response of repo usage line items does not directly map to a net usage line item
      usageTableData: MOCK_REPO_LINE_ITEMS,
      requestState: RequestState.IDLE,
      otherUsage: [],
    })

    const {user} = render(
      <UsageTable
        filters={{...DEFAULT_FILTERS, group: GROUP_SELECTIONS[4]}}
        isEnterpriseRoute
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )
    const expectedRepos = [
      'test-org-c/test-repo-c',
      'test-org-a/test-repo-a',
      'test-org-b/test-repo-b',
      'test-org-b/test-repo-a',
      'test-org-d/test-repo-d',
      'test-org-e/test-repo-e',
      'test-org-f/test-repo-f',
    ]
    const expectedBilledAmount = ['$4.00', '$3.60', '$3.00', '$3.00', '$2.00', '$2.00', '$2.00']

    const foundRepoCells = await screen.findAllByTestId('identifier-td')
    for (const [i, repo] of expectedRepos.entries()) {
      expect(foundRepoCells[i]).toContainElement(await screen.findByText(repo))
    }
    expect((await screen.findAllByTestId('gross-amount-td')).map(cell => cell.innerHTML)).toEqual(expectedBilledAmount)

    expect((await screen.findAllByTestId('billed-amount-td')).map(cell => cell.innerHTML)).toEqual([
      '$4.00',
      '$3.60',
      '$3.00',
      '$3.00',
      '$2.00',
      '$2.00',
      '$2.00',
    ])

    // expand sub table for repo a's usage
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(within(screen.getByTestId('usage-test-org-a-test-repo-a')).getByTestId('usage-details'))

    // mock the request we make when the sub table row is expanded for an repo
    mockFetch.mockRouteOnce(
      `/enterprises/github-inc/billing/net_usage?customer_id=${DEFAULT_FILTERS.customer.id}&group=${UsageGrouping.SKU}&period=${DEFAULT_FILTERS.period?.type}&query=repo%3Atest-org-a%2Ftest-repo-a`,
      {usage: [{...MOCK_ORG_LINE_ITEMS[0], grossAmount: 2}]},
    )

    await waitFor(() => {
      expect(within(screen.getByTestId('usage-test-org-a-test-repo-a')).getByTestId('usage-sub-table')).toBeVisible()
    })

    const expectedSubSKU = 'Actions Linux'
    const expectedSubBilledAmount = '$2.00'
    const expectedSubQuantity = '10 min'
    const expectedSubAppliedCostPerQuantity = '$0.20'

    const skuCell = await screen.findByTestId('sub-sku-td')
    expect(skuCell.innerHTML).toEqual(expectedSubSKU)

    const grossAmount = await screen.findByTestId('sub-gross-amount-td')
    expect(grossAmount.innerHTML).toEqual(expectedSubBilledAmount)

    const netAmount = await screen.findByTestId('sub-billed-amount-td')
    expect(netAmount.innerHTML).toEqual('N/A')

    const quantity = await screen.findByTestId('sub-quantity-td')
    expect(quantity.innerHTML).toEqual(expectedSubQuantity)

    const unitPrice = await screen.findByTestId('sub-applied-cost-per-quantity-td')
    expect(unitPrice.innerHTML).toEqual(expectedSubAppliedCostPerQuantity)

    // close sub table
    await user.click(within(screen.getByTestId('usage-test-org-a-test-repo-a')).getByTestId('usage-details'))
    await waitFor(() => {
      expect(screen.queryByTestId('usage-sub-table')).toBeNull()
    })
  })

  test('Renders usage by repo with only the repo name when group by repo is selected', async () => {
    jest.mocked(useUsageTableData).mockReturnValue({
      // @ts-expect-error - the returned response of repo usage line items does not directly map to a net usage line item
      usageTableData: MOCK_REPO_LINE_ITEMS,
      requestState: RequestState.IDLE,
      otherUsage: [],
    })

    const {user} = render(
      <UsageTable
        filters={{...DEFAULT_FILTERS, group: GROUP_SELECTIONS[4]}}
        isEnterpriseRoute={false}
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )
    const expectedRepos = ['test-repo-c', 'test-repo-b', 'test-repo-d', 'test-repo-e', 'test-repo-f']
    const expectedBilledAmount = ['$4.00', '$3.60', '$3.00', '$3.00', '$2.00', '$2.00', '$2.00']

    const foundRepoCells = await screen.findAllByTestId('identifier-td')
    // eslint-disable-next-line unused-imports/no-unused-vars
    for (const [i, repo] of expectedRepos.entries()) {
      const foundRepo = foundRepoCells.find(cell => cell.innerHTML.includes(repo))
      expect(foundRepo).toBeInTheDocument()
    }
    expect((await screen.findAllByTestId('gross-amount-td')).map(cell => cell.innerHTML)).toEqual(expectedBilledAmount)

    expect((await screen.findAllByTestId('billed-amount-td')).map(cell => cell.innerHTML)).toEqual([
      '$4.00',
      '$3.60',
      '$3.00',
      '$3.00',
      '$2.00',
      '$2.00',
      '$2.00',
    ])

    // expand sub table for repo a's usage
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(within(screen.getByTestId('usage-test-org-a-test-repo-a')).getByTestId('usage-details'))

    // mock the request we make when the sub table row is expanded for an repo
    mockFetch.mockRouteOnce(
      `/enterprises/github-inc/billing/net_usage?customer_id=${DEFAULT_FILTERS.customer.id}&group=${UsageGrouping.SKU}&period=${DEFAULT_FILTERS.period?.type}&query=repo%3Atest-org-a%2Ftest-repo-a`,
      {usage: [{...MOCK_ORG_LINE_ITEMS[0], grossAmount: 2}]},
    )

    await waitFor(() => {
      expect(within(screen.getByTestId('usage-test-org-a-test-repo-a')).getByTestId('usage-sub-table')).toBeVisible()
    })

    const expectedSubSKU = 'Actions Linux'
    const expectedSubBilledAmount = '$2.00'
    const expectedSubQuantity = '10 min'
    const expectedSubAppliedCostPerQuantity = '$0.20'

    const skuCell = await screen.findByTestId('sub-sku-td')
    expect(skuCell.innerHTML).toEqual(expectedSubSKU)

    const grossAmount = await screen.findByTestId('sub-gross-amount-td')
    expect(grossAmount.innerHTML).toEqual(expectedSubBilledAmount)

    const netAmount = await screen.findByTestId('sub-billed-amount-td')
    expect(netAmount.innerHTML).toEqual('N/A')

    const quantity = await screen.findByTestId('sub-quantity-td')
    expect(quantity.innerHTML).toEqual(expectedSubQuantity)

    const unitPrice = await screen.findByTestId('sub-applied-cost-per-quantity-td')
    expect(unitPrice.innerHTML).toEqual(expectedSubAppliedCostPerQuantity)

    // close sub table
    await user.click(within(screen.getByTestId('usage-test-org-a-test-repo-a')).getByTestId('usage-details'))
    await waitFor(() => {
      expect(screen.queryByTestId('usage-sub-table')).toBeNull()
    })
  })

  describe('loading states', () => {
    it('Renders a loading component in init state', async () => {
      jest.mocked(useUsageTableData).mockReturnValue({
        usageTableData: [],
        requestState: RequestState.INIT,
        otherUsage: [],
      })

      render(<UsageTable filters={DEFAULT_FILTERS} isEnterpriseRoute codingAgentEnabled={false} sparkEnabled={false} />)

      expect(await screen.findByTestId('usage-table-row-skeletons')).toBeVisible()
    })

    it('Renders a loading component while usage is being requested', async () => {
      jest.mocked(useUsageTableData).mockReturnValue({
        usageTableData: [],
        requestState: RequestState.LOADING,
        otherUsage: [],
      })

      render(<UsageTable filters={DEFAULT_FILTERS} isEnterpriseRoute codingAgentEnabled={false} sparkEnabled={false} />)

      expect(await screen.findByTestId('usage-table-row-skeletons')).toBeVisible()
    })

    it('Renders an error component when the usage request fails', async () => {
      jest.mocked(useUsageTableData).mockReturnValue({
        usageTableData: [],
        requestState: RequestState.ERROR,
        otherUsage: [],
      })

      render(<UsageTable filters={DEFAULT_FILTERS} isEnterpriseRoute codingAgentEnabled={false} sparkEnabled={false} />)

      expect(await screen.findByTestId('usage-loading-error')).toBeVisible()
    })
  })
})

describe('UsageTable for licensed SKUs with daily emissions', () => {
  beforeEach(() => {
    jest.mocked(useUsageTableData).mockReturnValue({
      usageTableData: LICENSE_SKU_MOCK_USAGE,
      requestState: RequestState.IDLE,
      otherUsage: [],
    })
  })

  test('Renders the correct data in the rows when grouped by SKU for the current month', async () => {
    render(
      <UsageTable
        filters={{
          customer: {
            id: '1',
            displayText: 'None',
          },
          group: {
            type: 2,
            displayText: 'SKU',
          },
          period: {
            type: 3,
            displayText: 'Current month',
          },
          searchQuery: '',
          product: undefined,
        }}
        isEnterpriseRoute
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )

    const skuCells = await screen.findAllByTestId('identifier-td')
    const quantityCells = await screen.findAllByTestId('quantity-td')
    const costPerQuantityCells = await screen.findAllByTestId('applied-cost-per-quantity-td')
    const grossAmountCells = await screen.findAllByTestId('gross-amount-td')
    const billedAmountCells = await screen.findAllByTestId('billed-amount-td')

    expect(skuCells[0]).toContainElement(await screen.findByText('Copilot Enterprise'))
    expect(quantityCells[0]).toHaveTextContent('5 licenses')
    expect(costPerQuantityCells[0]).toHaveTextContent('$1.258065')
    expect(grossAmountCells[0]).toHaveTextContent('$6.29')
    expect(billedAmountCells[0]).toHaveTextContent('$6.29')
  })

  test('shows the usage table subtitle', async () => {
    // force the current time to be March 15, 2025
    jest.useFakeTimers().setSystemTime(new Date('2025-03-15'))

    render(<UsageTable filters={DEFAULT_FILTERS} isEnterpriseRoute codingAgentEnabled={false} sparkEnabled={false} />)

    expect(
      await screen.findByText(
        'Usage for Mar 1 - Mar 31, 2025. For license-based products, the price/unit is a prorated portion of the monthly price.',
      ),
    ).toBeVisible()
  })
})

describe('UsageTable with licensed SKU usage for a cost center', () => {
  test('Renders the correct data in the sub-table when grouped by cost center for current month', async () => {
    jest.mocked(useUsageTableData).mockReturnValue({
      usageTableData: LICENSE_SKU_WITH_COST_CENTER_NET_USAGE,
      requestState: RequestState.IDLE,
      otherUsage: [],
    })
    const filters = {...DEFAULT_FILTERS, group: GROUP_SELECTIONS[5]}
    const {user} = render(
      <UsageTable filters={filters} isEnterpriseRoute codingAgentEnabled={false} sparkEnabled={false} />,
    )
    /*
      Test data:
      - Cost center has 1 seat assigned for 3 days in April.
      - $39/month per seat = $1.30/day per seat (30-day month).
      - Total: $1.30/day * 3 days * 1 seat = $3.90.
    */
    const expectedValues = {
      name: 'licensing test',
      expectedSku: 'Copilot Enterprise',
      expectedQuantity: '1 license',
      expectedCost: '$3.90',
      expectedGrossAmount: '$3.90',
      expectedBilledAmount: '$3.90',
      entityId: '79e7ba2d-61c1-4170-b9b9-63ec44c82f07',
    }

    const costCenterUsage = LICENSE_SKU_WITH_COST_CENTER_NET_USAGE.filter(
      item => item.entityId === expectedValues.entityId,
    )

    const detailsElement = within(screen.getByTestId(`usage-${expectedValues.entityId}`)).getByTestId('usage-details')
    expect(detailsElement).toBeInTheDocument()

    // mock the request we make when the sub table row is expanded for a cost center
    mockFetch.mockRouteOnce(
      `/enterprises/github-inc/billing/net_usage?customer_id=${expectedValues.entityId}&group=2&period=3&query=cost_center%3Anone`,
      {usage: costCenterUsage},
    )

    await user.click(detailsElement)

    // Wait for the sub-table to appear
    await waitFor(() => {
      expect(
        within(screen.getByTestId(`usage-${expectedValues.entityId}`)).getByTestId('usage-sub-table'),
      ).toBeVisible()
    })

    const skuCells = screen.getAllByTestId(`sub-sku-td`)
    const quantityCells = screen.getAllByTestId(`sub-quantity-td`)
    const costPerQuantityCells = screen.getAllByTestId(`sub-applied-cost-per-quantity-td`)
    const grossAmountSubCells = screen.getAllByTestId(`sub-gross-amount-td`)
    const billedAmountSubCells = screen.getAllByTestId(`sub-billed-amount-td`)

    expect(skuCells[0]).toHaveTextContent(expectedValues.expectedSku)
    expect(quantityCells[0]).toHaveTextContent(expectedValues.expectedQuantity)
    expect(costPerQuantityCells[0]).toHaveTextContent(expectedValues.expectedCost)
    expect(grossAmountSubCells[0]).toHaveTextContent(expectedValues.expectedGrossAmount)
    expect(billedAmountSubCells[0]).toHaveTextContent(expectedValues.expectedBilledAmount)
  })

  test('Renders the correct data in the table and sub-table when grouped by product for current month', async () => {
    const {user} = render(
      <UsageTable
        filters={{...DEFAULT_FILTERS, group: GROUP_SELECTIONS[1]}}
        isEnterpriseRoute
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )

    const productCells = await screen.findAllByTestId('identifier-td')
    const grossAmountCells = await screen.findAllByTestId('gross-amount-td')
    const billedAmountCells = await screen.findAllByTestId('billed-amount-td')

    expect(productCells[0]).toContainElement(await screen.findByText('Copilot'))
    expect(grossAmountCells[0]).toHaveTextContent('$15.60')
    expect(billedAmountCells[0]).toHaveTextContent('$15.60')

    // expand sub table
    const detailsElement = await screen.findByTestId('usage-details')
    expect(detailsElement).toBeInTheDocument()
    await user.click(detailsElement)
    await waitFor(() => {
      expect(screen.getByTestId('usage-sub-table')).toBeVisible()
    })
    const skuCells = screen.getAllByTestId('sub-sku-td')
    const quantityCells = screen.getAllByTestId('sub-quantity-td')
    const costPerQuantityCells = screen.getAllByTestId('sub-applied-cost-per-quantity-td')
    const grossAmountSubCells = screen.getAllByTestId('sub-gross-amount-td')
    const billedAmountSubCells = screen.getAllByTestId('sub-billed-amount-td')

    expect(skuCells[0]).toHaveTextContent('Copilot Enterprise')
    expect(quantityCells[0]).toHaveTextContent('4 licenses')
    expect(costPerQuantityCells[0]).toHaveTextContent('$3.90')
    expect(grossAmountSubCells[0]).toHaveTextContent('$15.60')
    expect(billedAmountSubCells[0]).toHaveTextContent('$15.60')
  })

  test('Renders the correct data in the rows when grouped by SKU for the current month', async () => {
    render(
      <UsageTable
        filters={{...DEFAULT_FILTERS, group: GROUP_SELECTIONS[2]}}
        isEnterpriseRoute
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )

    const skuCells = await screen.findAllByTestId('identifier-td')
    const quantityCells = await screen.findAllByTestId('quantity-td')
    const costPerQuantityCells = await screen.findAllByTestId('applied-cost-per-quantity-td')
    const grossAmountCells = await screen.findAllByTestId('gross-amount-td')
    const billedAmountCells = await screen.findAllByTestId('billed-amount-td')

    expect(skuCells[0]).toContainElement(await screen.findByText('Copilot Enterprise'))
    expect(grossAmountCells[0]).toHaveTextContent('$15.60')
    expect(billedAmountCells[0]).toHaveTextContent('$15.60')
    expect(quantityCells[0]).toHaveTextContent('4 licenses')
    expect(costPerQuantityCells[0]).toHaveTextContent('$3.90')
  })

  test("Renders the correct data when grouped by cost center and there's a different number of usage days for the same SKU", async () => {
    jest.mocked(useUsageTableData).mockReturnValue({
      usageTableData: LICENSE_SKU_WITH_COST_CENTER_NET_USAGE_DIFFERENT_DAYS,
      requestState: RequestState.IDLE,
      otherUsage: [],
    })

    const filters = {...DEFAULT_FILTERS, group: GROUP_SELECTIONS[5]}
    const {user} = render(
      <UsageTable filters={filters} isEnterpriseRoute codingAgentEnabled={false} sparkEnabled={false} />,
    )

    const expectedValues = {
      name: 'licensing test',
      expectedSku: 'Copilot Enterprise',
      expectedQuantity: '1 license',
      expectedCost: '$1.30',
      expectedGrossAmount: '$1.30',
      expectedBilledAmount: '$1.30',
      entityId: '79e7ba2d-61c1-4170-b9b9-63ec44c82f07',
    }

    const costCenterData = LICENSE_SKU_WITH_COST_CENTER_NET_USAGE_DIFFERENT_DAYS.filter(
      item => item.entityId === expectedValues.entityId,
    )

    const detailsElement = within(screen.getByTestId(`usage-${expectedValues.entityId}`)).getByTestId('usage-details')
    expect(detailsElement).toBeInTheDocument()

    // mock the request we make when the sub table row is expanded for a cost center
    mockFetch.mockRouteOnce(
      `/enterprises/github-inc/billing/net_usage?customer_id=${expectedValues.entityId}&group=2&period=3&query=cost_center%3Anone`,
      {usage: costCenterData},
    )

    await user.click(detailsElement)
    await waitFor(() => {
      expect(
        within(screen.getByTestId(`usage-${expectedValues.entityId}`)).getByTestId('usage-sub-table'),
      ).toBeVisible()
    })

    const skuCells = screen.getAllByTestId(`sub-sku-td`)
    const quantityCells = screen.getAllByTestId(`sub-quantity-td`)
    const costPerQuantityCells = screen.getAllByTestId(`sub-applied-cost-per-quantity-td`)
    const grossAmountSubCells = screen.getAllByTestId(`sub-gross-amount-td`)
    const billedAmountSubCells = screen.getAllByTestId(`sub-billed-amount-td`)

    expect(skuCells[0]).toHaveTextContent(expectedValues.expectedSku)
    expect(quantityCells[0]).toHaveTextContent(expectedValues.expectedQuantity)
    expect(costPerQuantityCells[0]).toHaveTextContent(expectedValues.expectedCost)
    expect(grossAmountSubCells[0]).toHaveTextContent(expectedValues.expectedGrossAmount)
    expect(billedAmountSubCells[0]).toHaveTextContent(expectedValues.expectedBilledAmount)
  })
})

describe('UsageTable with licensed SKU usage when seats are added partway through a month', () => {
  beforeEach(() => {
    jest.mocked(useUsageTableData).mockReturnValue({
      usageTableData: LICENSE_SKU_USAGE_PARTIAL_MONTH,
      requestState: RequestState.IDLE,
      otherUsage: [],
    })
  })
  test('Renders the correct data in the sub table when grouped by product for the current month', async () => {
    const {user} = render(
      <UsageTable
        filters={{...DEFAULT_FILTERS, group: GROUP_SELECTIONS[1]}}
        isEnterpriseRoute
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )

    const productCells = await screen.findAllByTestId('identifier-td')
    const grossAmountCells = await screen.findAllByTestId('gross-amount-td')
    const billedAmountCells = await screen.findAllByTestId('billed-amount-td')

    expect(productCells[0]).toContainElement(await screen.findByText('Copilot'))
    expect(grossAmountCells[0]).toHaveTextContent('$5.20')
    expect(billedAmountCells[0]).toHaveTextContent('$5.20')

    // expand sub table
    const detailsElement = await screen.findByTestId('usage-details')
    expect(detailsElement).toBeInTheDocument()
    await user.click(detailsElement)
    await waitFor(() => {
      expect(screen.getByTestId('usage-sub-table')).toBeVisible()
    })
    const skuCells = screen.getAllByTestId('sub-sku-td')
    const quantityCells = screen.getAllByTestId('sub-quantity-td')
    const costPerQuantityCells = screen.getAllByTestId('sub-applied-cost-per-quantity-td')
    const grossAmountSubCells = screen.getAllByTestId('sub-gross-amount-td')
    const billedAmountSubCells = screen.getAllByTestId('sub-billed-amount-td')

    /*
    For this test data:
    - An enterprise has 2 seats assigned starting on April 29.
    - One seat costs $39 per month, which is $1.30 per day in April (30 days).
    - Total charge: $1.30 per day * 2 days * 2 seats = $5.20 month-to-date.
    */
    expect(skuCells[0]).toHaveTextContent('Copilot Enterprise')
    expect(quantityCells[0]).toHaveTextContent('2 licenses')
    expect(costPerQuantityCells[0]).toHaveTextContent('$2.60')
    expect(grossAmountSubCells[0]).toHaveTextContent('$5.20')
    expect(billedAmountSubCells[0]).toHaveTextContent('$5.20')
  })

  test('Renders the correct data in the rows when grouped by SKU for the current month', async () => {
    render(
      <UsageTable
        filters={{...DEFAULT_FILTERS, group: GROUP_SELECTIONS[2]}}
        isEnterpriseRoute
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )

    const skuCells = await screen.findAllByTestId('identifier-td')
    const quantityCells = await screen.findAllByTestId('quantity-td')
    const costPerQuantityCells = await screen.findAllByTestId('applied-cost-per-quantity-td')
    const grossAmountCells = await screen.findAllByTestId('gross-amount-td')
    const billedAmountCells = await screen.findAllByTestId('billed-amount-td')

    expect(skuCells[0]).toContainElement(await screen.findByText('Copilot Enterprise'))
    expect(grossAmountCells[0]).toHaveTextContent('$5.20')
    expect(billedAmountCells[0]).toHaveTextContent('$5.20')
    expect(quantityCells[0]).toHaveTextContent('2 licenses')
    expect(costPerQuantityCells[0]).toHaveTextContent('$2.60')
  })

  test('Renders the correct data in the sub-table when grouped by cost center for current month', async () => {
    const filters = {...DEFAULT_FILTERS, group: GROUP_SELECTIONS[5]}
    const {user} = render(
      <UsageTable filters={filters} isEnterpriseRoute codingAgentEnabled={false} sparkEnabled={false} />,
    )

    const expectedValues = {
      name: 'Enterprise Only',
      expectedSku: 'Copilot Enterprise',
      expectedQuantity: '2 licenses',
      expectedCost: '$2.60',
      expectedGrossAmount: '$5.20',
      expectedBilledAmount: '$5.20',
      entityId: '1',
    }

    const detailsElement = within(screen.getByTestId(`usage-${expectedValues.entityId}`)).getByTestId('usage-details')
    expect(detailsElement).toBeInTheDocument()

    // mock the request we make when the sub table row is expanded for a cost center
    mockFetch.mockRouteOnce(
      `/enterprises/github-inc/billing/net_usage?customer_id=${expectedValues.entityId}&group=2&period=3&query=cost_center%3Anone`,
      {usage: LICENSE_SKU_USAGE_PARTIAL_MONTH},
    )

    await user.click(detailsElement)
    await waitFor(() => {
      expect(
        within(screen.getByTestId(`usage-${expectedValues.entityId}`)).getByTestId('usage-sub-table'),
      ).toBeVisible()
    })

    const skuCells = screen.getAllByTestId(`sub-sku-td`)
    const quantityCells = screen.getAllByTestId(`sub-quantity-td`)
    const costPerQuantityCells = screen.getAllByTestId(`sub-applied-cost-per-quantity-td`)
    const grossAmountSubCells = screen.getAllByTestId(`sub-gross-amount-td`)
    const billedAmountSubCells = screen.getAllByTestId(`sub-billed-amount-td`)

    expect(skuCells[0]).toHaveTextContent(expectedValues.expectedSku)
    expect(quantityCells[0]).toHaveTextContent(expectedValues.expectedQuantity)
    expect(costPerQuantityCells[0]).toHaveTextContent(expectedValues.expectedCost)
    expect(grossAmountSubCells[0]).toHaveTextContent(expectedValues.expectedGrossAmount)
    expect(billedAmountSubCells[0]).toHaveTextContent(expectedValues.expectedBilledAmount)
  })
})

describe('UsageTable when grouped by org for licensed SKU usage', () => {
  beforeEach(() => {
    jest.mocked(useUsageTableData).mockReturnValue({
      // @ts-expect-error - the returned response of repo usage line items does not directly map to a net usage line item
      usageTableData: LICENSE_SKU_ORG_DATA,
      requestState: RequestState.IDLE,
      otherUsage: [],
    })
  })

  test('Renders the correct data in the sub-table when grouped by org for current month', async () => {
    const {user} = render(
      <UsageTable
        filters={{...DEFAULT_FILTERS, group: GROUP_SELECTIONS[3]}}
        isEnterpriseRoute
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )
    /*
      Test data:
      - An org has 2 seats assigned for 3 days in April.
      - $39/month per seat = $1.30/day per seat (30-day month).
      - Total: $1.30/day * 3 days * 2 seats = $7.80 month-to-date.
    */
    const expectedValues = {
      name: 'github',
      expectedSku: 'Copilot Enterprise',
      expectedQuantity: '2 licenses',
      expectedCost: '$3.90',
      expectedGrossAmount: '$7.80',
      expectedBilledAmount: '$7.80',
    }

    const detailsElement = within(screen.getByTestId(`usage-${expectedValues.name}`)).getByTestId('usage-details')
    expect(detailsElement).toBeInTheDocument()

    // mock the request we make when the sub table row is expanded for an org when group by org is selected
    mockFetch.mockRouteOnce(
      `/enterprises/github-inc/billing/net_usage?customer_id=1&group=2&period=3&query=org%3Agithub`,
      {usage: ORG_ROW_LICENSE_SKU_DATA},
    )

    await user.click(detailsElement)
    await waitFor(() => {
      expect(within(screen.getByTestId(`usage-${expectedValues.name}`)).getByTestId('usage-sub-table')).toBeVisible()
    })

    const skuCells = screen.getAllByTestId(`sub-sku-td`)
    const quantityCells = screen.getAllByTestId(`sub-quantity-td`)
    const costPerQuantityCells = screen.getAllByTestId(`sub-applied-cost-per-quantity-td`)
    const grossAmountSubCells = screen.getAllByTestId(`sub-gross-amount-td`)
    const billedAmountSubCells = screen.getAllByTestId(`sub-billed-amount-td`)

    expect(skuCells[1]).toHaveTextContent(expectedValues.expectedSku)
    expect(quantityCells[1]).toHaveTextContent(expectedValues.expectedQuantity)
    expect(costPerQuantityCells[1]).toHaveTextContent(expectedValues.expectedCost)
    expect(grossAmountSubCells[1]).toHaveTextContent(expectedValues.expectedGrossAmount)
    expect(billedAmountSubCells[1]).toHaveTextContent(expectedValues.expectedBilledAmount)
  })
})
