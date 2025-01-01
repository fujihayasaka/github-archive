import {
  buildFieldMetricsQueryKey,
  buildPaginatedTotalCountsQueryKey,
  buildSliceDataQueryKey,
  type FieldMetricsQueryKey,
  fieldMetricsQueryKey,
  paginatedMemexItemsQueryKey,
  type SliceByDataQueryKey,
  sliceByDataQueryKey,
  type TotalCountsDataQueryKey,
  totalCountsQueryKey,
} from '../../../client/state-providers/memex-items/queries/query-keys'
import type {
  FieldMetricsQueryVariables,
  PaginatedMemexItemsQueryVariables,
  SliceByQueryVariables,
  TotalCountsQueryVariables,
} from '../../../client/state-providers/memex-items/queries/types'

const variables: PaginatedMemexItemsQueryVariables = {
  q: 'is:issue',
  sortedBy: [],
  sliceByValue: 'sliceByValue',
  fieldIds: [1, 2, 3],
}

describe('buildSliceDataQueryKey', () => {
  it('sets sliceByValue and fieldIds to undefined', () => {
    const expectedSliceByVariables: SliceByQueryVariables = {
      ...variables,
      sliceByValue: undefined,
      fieldIds: undefined,
    }
    const expectedQueryKey: SliceByDataQueryKey = [
      'memex',
      paginatedMemexItemsQueryKey,
      expectedSliceByVariables,
      sliceByDataQueryKey,
    ]
    const queryKey = buildSliceDataQueryKey(variables)
    expect(queryKey).toEqual(expectedQueryKey)
  })
})

describe('buildPaginatedTotalCountsQueryKey', () => {
  it('sets fieldIds to undefined', () => {
    const expectedTotalCountsVariables: TotalCountsQueryVariables = {
      ...variables,
      fieldIds: undefined,
    }
    const expectedQueryKey: TotalCountsDataQueryKey = [
      'memex',
      paginatedMemexItemsQueryKey,
      expectedTotalCountsVariables,
      totalCountsQueryKey,
    ]
    const queryKey = buildPaginatedTotalCountsQueryKey(variables)
    expect(queryKey).toEqual(expectedQueryKey)
  })
})

describe('buildFieldMetricsQueryKey', () => {
  it('sets fieldIds to undefined', () => {
    const expectedFieldMetricsVariables: FieldMetricsQueryVariables = {
      ...variables,
      fieldIds: undefined,
    }
    const expectedQueryKey: FieldMetricsQueryKey = [
      'memex',
      paginatedMemexItemsQueryKey,
      expectedFieldMetricsVariables,
      fieldMetricsQueryKey,
    ]
    const queryKey = buildFieldMetricsQueryKey(variables)
    expect(queryKey).toEqual(expectedQueryKey)
  })
})
