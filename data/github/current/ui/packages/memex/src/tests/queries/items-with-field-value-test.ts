import {renderHook, waitFor} from '@testing-library/react'

import type {PaginatedItemsData} from '../../client/api/memex-items/paginated-views'
import {createColumnModel} from '../../client/models/column-model'
import {useItemsWithFieldValueCountQuery} from '../../client/queries/items-with-field-value'
import {customColumnFactory} from '../factories/columns/custom-column-factory'
import {
  expectRequestToHaveBeenCalledWithQueryParams,
  stubGetPaginatedItemsMethodAndCaptureQueryParameters,
} from '../mocks/api/memex-items'
import {QueryClientWrapper} from '../test-app-wrapper'

describe(`useItemsWithFieldValueCountQuery`, () => {
  it('returns totalCount from paginated_items request', async () => {
    const expectedResponse: PaginatedItemsData = {
      nodes: [],
      pageInfo: {hasNextPage: false, hasPreviousPage: false},
      totalCount: {isApproximate: false, value: 200},
    }

    // Set up mock request handler
    const requestStub = stubGetPaginatedItemsMethodAndCaptureQueryParameters(expectedResponse)

    const columnModel = createColumnModel(customColumnFactory.build({name: 'MyColumn'}))
    const {result, rerender} = renderHook(() => useItemsWithFieldValueCountQuery(columnModel), {
      wrapper: QueryClientWrapper,
    })

    expect(result.current.data).toBeUndefined()

    await waitFor(() => {
      // Assert request stub is called with correct request parameters
      expectRequestToHaveBeenCalledWithQueryParams(requestStub, {q: 'has:MyColumn', first: 1})
    })

    rerender()

    expect(result.current.data).toBe(200)
  })
})
