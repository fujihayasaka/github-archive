import {renderHook, waitFor} from '@testing-library/react'
import {doRequest} from '../../../hooks/use-request'
import useUsageSubTableData from '../../../hooks/usage/use-usage-sub-table-data'
import {
  DEFAULT_FILTERS,
  GROUP_SELECTIONS,
  MOCK_LINE_ITEMS,
  PRODUCT_USAGE_LINE_ITEM,
  REPO_USAGE_LINE_ITEM,
  REPO_USAGE_LINE_ITEM_WITH_SPACES,
  USAGE_LINE_ITEM,
} from '../../../test-utils/mock-data'

import type {GroupSelection, ProductUsageLineItem, RepoUsageLineItem, UsageLineItem} from '../../../types/usage'

jest.mock('../../../hooks/use-request', () => ({
  doRequest: jest.fn(),
}))

describe('UseUsageSubTableData', () => {
  beforeEach(() => {
    ;(doRequest as jest.Mock).mockResolvedValue({
      data: {usage: MOCK_LINE_ITEMS},
      ok: true,
      statusCode: 200,
    })
  })

  type HookParams = {
    lineItem: ProductUsageLineItem | RepoUsageLineItem | UsageLineItem
    group?: GroupSelection
    searchQuery?: string
  }

  const hook = ({lineItem, group, searchQuery}: HookParams) => {
    const filters = DEFAULT_FILTERS
    if (group) filters.group = group
    filters.searchQuery = searchQuery || ''

    return renderHook(() => {
      return useUsageSubTableData({
        lineItem,
        open: true,
        rawUsage: MOCK_LINE_ITEMS,
        filters,
      })
    })
  }

  describe('getSearchQuery', () => {
    describe('for a product usage line item', () => {
      const lineItem = PRODUCT_USAGE_LINE_ITEM
      const group = GROUP_SELECTIONS[1] // Product

      it('includes the product type in the searchQuery', async () => {
        const {result} = hook({lineItem, group, searchQuery: ''})

        await waitFor(() => expect(result.current.getSearchQuery()).toEqual('product:actions'))
      })

      it('passes the filter searchQuery through to the product searchQuery', async () => {
        const {result} = hook({lineItem, group, searchQuery: 'repo:demo'})

        await waitFor(() => expect(result.current.getSearchQuery()).toEqual('product:actions repo:demo'))
      })
    })

    describe('grouping by cost center', () => {
      const lineItem = PRODUCT_USAGE_LINE_ITEM
      const group = GROUP_SELECTIONS[5] // Cost center
      const searchQuery = ''

      it('sets cost_center:none as the query when expanding a row when the table is grouped by cost centers', async () => {
        const {result} = hook({
          lineItem,
          group,
          searchQuery,
        })

        await waitFor(() => expect(result.current.getSearchQuery()).toEqual('cost_center:none'))
      })

      it('sets cost_center:none org:demo as the query when expanding a row when the table is grouped by cost centers and filtered by org', async () => {
        const {result} = hook({
          lineItem,
          group,
          searchQuery: 'org:demo',
        })

        await waitFor(() => expect(result.current.getSearchQuery()).toEqual('cost_center:none org:demo'))
      })
    })

    describe('for a generic usage line item', () => {
      it('returns an empty searchQuery', async () => {
        const {result} = hook({
          lineItem: USAGE_LINE_ITEM,
          group: GROUP_SELECTIONS[4], // Repo
          searchQuery: '',
        })

        await waitFor(() => expect(result.current.getSearchQuery()).toEqual(''))
      })
    })

    describe('for a repo usage line item', () => {
      it('includes the repo org in the searchQuery when grouping by org', async () => {
        const {result} = hook({
          lineItem: REPO_USAGE_LINE_ITEM,
          group: GROUP_SELECTIONS[3], // Org
          searchQuery: 'org:somethingrandom',
        })

        await waitFor(() => expect(result.current.getSearchQuery()).toEqual('org:test-org-a'))
      })

      it('includes the repo in the searchQuery when grouping by repo', async () => {
        const {result} = hook({
          lineItem: REPO_USAGE_LINE_ITEM,
          group: GROUP_SELECTIONS[4], // Repo
          searchQuery: 'org:myorg',
        })

        await waitFor(() => expect(result.current.getSearchQuery()).toEqual('repo:test-org-a/test-repo-a'))
      })
    })

    it('correctly formats org names that have spaces in them', async () => {
      const {result} = hook({
        lineItem: REPO_USAGE_LINE_ITEM_WITH_SPACES,
        group: GROUP_SELECTIONS[3], // Org
        searchQuery: '',
      })

      await waitFor(() => expect(result.current.getSearchQuery()).toEqual('org:Test-Org-A'))
    })

    it('correctly formats repo names when their owning org has spaces in its name', async () => {
      const {result} = hook({
        lineItem: REPO_USAGE_LINE_ITEM_WITH_SPACES,
        group: GROUP_SELECTIONS[4], // Repo
        searchQuery: '',
      })

      await waitFor(() => expect(result.current.getSearchQuery()).toEqual('repo:Test-Org-A/test-repo-a'))
    })
  })
})
