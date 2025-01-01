import {
  DEFAULT_FILTERS,
  GROUP_SELECTIONS,
  MOCK_LINE_ITEMS,
  MOCK_LINE_ITEMS_COSTCENTERS,
  MOCK_ORG_LINE_ITEMS,
  MOCK_REPO_LINE_ITEMS,
  MOCK_REPO_PAGINATED_LINE_ITEMS,
  PERIOD_SELECTIONS,
} from '../../../test-utils/mock-data'
import {fireEvent, screen, waitFor, within} from '@testing-library/react'

import {RequestState} from '../../../enums'
import {UsageTable} from '../../../components/usage'
import {render} from '@github-ui/react-core/test-utils'
import {mockFetch} from '@github-ui/mock-fetch'
import useUsageTableData from '../../../hooks/usage/use-usage-table-data'

import type {NetUsageLineItem} from '../../../types/usage'
import {getPageCount} from '../../../components/usage/UsageTable/UsageTable'

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
  totalLineItemsCount: MOCK_LINE_ITEMS.length,
  requestState: RequestState.IDLE,
})

describe('UsageTable', () => {
  test('Renders usage by SKU when group by SKU is selected', async () => {
    render(<UsageTable filters={{...DEFAULT_FILTERS, group: GROUP_SELECTIONS[2]}} />)

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
    const {user} = render(<UsageTable filters={{...DEFAULT_FILTERS, group: GROUP_SELECTIONS[1]}} />)

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
      totalLineItemsCount: MOCK_LINE_ITEMS_COSTCENTERS.length,
      requestState: RequestState.IDLE,
    })
    render(<UsageTable filters={{...DEFAULT_FILTERS, group: GROUP_SELECTIONS[5]}} />)

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
      const {user} = render(<UsageTable filters={{...DEFAULT_FILTERS, period: PERIOD_SELECTIONS[2]}} />)
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
      const {user} = render(<UsageTable filters={{...DEFAULT_FILTERS, period: PERIOD_SELECTIONS[4]}} />)
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
    render(<UsageTable filters={{...DEFAULT_FILTERS, period: PERIOD_SELECTIONS[1]}} />)
    const foundDateCells = await screen.findAllByTestId('identifier-td')
    const expectedDates = ['Mar 1, 2023', 'Apr 2, 2023', 'May 3, 2023']
    const expectedBilledAmount = ['$2.59', '$3.00', '$10.10']

    for (const [i, date] of expectedDates.entries()) {
      expect(foundDateCells[i]).toContainElement(await screen.findByText(date))
    }

    expect((await screen.findAllByTestId('billed-amount-td')).map(cell => cell.innerHTML)).toEqual(expectedBilledAmount)
  })

  test('Renders usage with day precision when last month is selected', async () => {
    render(<UsageTable filters={{...DEFAULT_FILTERS, period: PERIOD_SELECTIONS[3]}} />)
    const foundDateCells = await screen.findAllByTestId('identifier-td')
    const expectedDates = ['Mar 1, 2023', 'Apr 2, 2023', 'May 3, 2023']
    const expectedBilledAmount = ['$2.59', '$3.00', '$10.10']

    for (const [i, date] of expectedDates.entries()) {
      expect(foundDateCells[i]).toContainElement(await screen.findByText(date))
    }

    expect((await screen.findAllByTestId('billed-amount-td')).map(cell => cell.innerHTML)).toEqual(expectedBilledAmount)
  })

  test('Renders usage with hour precision when current day is selected', async () => {
    render(<UsageTable filters={{...DEFAULT_FILTERS, period: PERIOD_SELECTIONS[0]}} />)
    const foundDateCells = await screen.findAllByTestId('identifier-td')
    const expectedDates = ['8 AM', '9 AM', '10 AM']
    const expectedBilledAmount = ['$2.59', '$3.00', '$10.10']

    for (const [i, date] of expectedDates.entries()) {
      expect(foundDateCells[i]).toContainElement(await screen.findByText(date))
    }

    expect((await screen.findAllByTestId('billed-amount-td')).map(cell => cell.innerHTML)).toEqual(expectedBilledAmount)
  })

  test('Renders usage with pagination when group by repo is selected', async () => {
    jest.mocked(useUsageTableData).mockReturnValue({
      // @ts-expect-error - the returned response of repo usage line items does not directly map to a net usage line item
      usageTableData: MOCK_REPO_PAGINATED_LINE_ITEMS,
      totalLineItemsCount: 35,
      requestState: RequestState.IDLE,
    })

    render(<UsageTable filters={{...DEFAULT_FILTERS, group: GROUP_SELECTIONS[4]}} />)

    const pagination = await screen.findByLabelText('Pagination')
    const previousButton = await screen.findByText('Previous')
    const nextLink = await screen.findByLabelText('Next Page')
    const page1Link = await screen.findByLabelText('Page 1')
    const page2Link = await screen.findByLabelText('Page 2')
    const page3Link = await screen.findByLabelText('Page 3...')

    expect(pagination).toBeInTheDocument()
    expect(previousButton).toBeInTheDocument()
    expect(nextLink).toBeInTheDocument()
    expect(page1Link).toBeInTheDocument()
    expect(page2Link).toBeInTheDocument()
    expect(page3Link).toBeInTheDocument()

    const usageTable = await screen.findByTestId('usage-table')
    const usageTableRows = await screen.findByTestId('usage-table-rows')
    const rowLineItems = within(usageTableRows).queryAllByTestId(/test-repo-/)

    expect(usageTable).toBeInTheDocument()
    expect(rowLineItems.length).toBe(MOCK_REPO_PAGINATED_LINE_ITEMS.length)
  })
})

describe('UsageTable when grouping by org or repo', () => {
  test('Renders usage by organization when group by organization is selected', async () => {
    jest.mocked(useUsageTableData).mockReturnValue({
      // @ts-expect-error - the returned response of repo usage line items does not directly map to a net usage line item
      usageTableData: MOCK_REPO_LINE_ITEMS,
      totalLineItemsCount: MOCK_REPO_LINE_ITEMS.length,
      requestState: RequestState.IDLE,
    })

    const {user} = render(<UsageTable filters={{...DEFAULT_FILTERS, group: GROUP_SELECTIONS[3]}} />)
    const expectedOrgs = ['test-org-a', 'test-org-b', 'test-org-c', 'test-org-d', 'test-org-e', 'test-org-f']
    const expectedBilledAmount = ['$3.60', '$6.00', '$4.00', '$2.00', '$2.00', '$2.00']

    const foundOrgCells = await screen.findAllByTestId('identifier-td')
    for (const [i, org] of expectedOrgs.entries()) {
      expect(foundOrgCells[i]).toContainElement(await screen.findByText(org))
    }
    expect((await screen.findAllByTestId('gross-amount-td')).map(cell => cell.innerHTML)).toEqual(expectedBilledAmount)

    // We do not show billed amount (net) for org/repo groupings
    expect((await screen.findAllByTestId('billed-amount-td')).map(cell => cell.innerHTML)).toEqual([
      'N/A',
      'N/A',
      'N/A',
      'N/A',
      'N/A',
      'N/A',
    ])

    // mock the request we make when the sub table row is expanded for an org
    mockFetch.mockRouteOnce(
      `/enterprises/github-inc/billing/usage?customer_id=${DEFAULT_FILTERS.customer.id}&group=${GROUP_SELECTIONS[2]?.type}&period=${DEFAULT_FILTERS.period?.type}&query=org%3Atest-org-a`,
      {usage: MOCK_ORG_LINE_ITEMS},
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
      totalLineItemsCount: MOCK_REPO_LINE_ITEMS.length,
      requestState: RequestState.IDLE,
    })

    const {user} = render(<UsageTable filters={{...DEFAULT_FILTERS, group: GROUP_SELECTIONS[4]}} />)
    const expectedRepos = [
      'test-org-a/test-repo-a',
      'test-org-b/test-repo-b',
      'test-org-b/test-repo-a',
      'test-org-c/test-repo-c',
      'test-org-d/test-repo-d',
      'test-org-e/test-repo-e',
      'test-org-f/test-repo-f',
    ]
    const expectedBilledAmount = ['$3.60', '$3.00', '$3.00', '$4.00', '$2.00', '$2.00', '$2.00']

    const foundRepoCells = await screen.findAllByTestId('identifier-td')
    for (const [i, repo] of expectedRepos.entries()) {
      expect(foundRepoCells[i]).toContainElement(await screen.findByText(repo))
    }
    expect((await screen.findAllByTestId('gross-amount-td')).map(cell => cell.innerHTML)).toEqual(expectedBilledAmount)

    // We do not show billed amount (net) for org/repo groupings
    expect((await screen.findAllByTestId('billed-amount-td')).map(cell => cell.innerHTML)).toEqual([
      'N/A',
      'N/A',
      'N/A',
      'N/A',
      'N/A',
      'N/A',
      'N/A',
    ])

    // expand sub table for repo a's usage
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(within(screen.getByTestId('usage-test-org-a-test-repo-a')).getByTestId('usage-details'))
    // await user.click(within(screen.getByTestId('usage-test-org-a-test-repo-a')).getByTestId('usage-details'))

    // mock the request we make when the sub table row is expanded for an repo
    mockFetch.mockRouteOnce(
      `/enterprises/github-inc/billing/usage?customer_id=${DEFAULT_FILTERS.customer.id}&group=${GROUP_SELECTIONS[2]?.type}&period=${DEFAULT_FILTERS.period?.type}&query=repo%3Atest-org-a%2Ftest-repo-a`,
      {usage: MOCK_ORG_LINE_ITEMS},
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
        totalLineItemsCount: 0,
        requestState: RequestState.INIT,
      })

      render(<UsageTable filters={DEFAULT_FILTERS} />)

      expect(await screen.findByTestId('usage-table-row-skeletons')).toBeVisible()
    })

    it('Renders a loading component while usage is being requested', async () => {
      jest.mocked(useUsageTableData).mockReturnValue({
        usageTableData: [],
        totalLineItemsCount: 0,
        requestState: RequestState.LOADING,
      })

      render(<UsageTable filters={DEFAULT_FILTERS} />)

      expect(await screen.findByTestId('usage-table-row-skeletons')).toBeVisible()
    })

    it('Renders an error component when the usage request fails', async () => {
      jest.mocked(useUsageTableData).mockReturnValue({
        usageTableData: [],
        totalLineItemsCount: 0,
        requestState: RequestState.ERROR,
      })

      render(<UsageTable filters={DEFAULT_FILTERS} />)

      expect(await screen.findByTestId('usage-loading-error')).toBeVisible()
    })
  })
})

describe('getPageCount', () => {
  it('returns the correct page count', () => {
    expect(getPageCount(35, 10)).toBe(4)
    expect(getPageCount(35, 5)).toBe(7)
    expect(getPageCount(35, 35)).toBe(1)
  })
})
