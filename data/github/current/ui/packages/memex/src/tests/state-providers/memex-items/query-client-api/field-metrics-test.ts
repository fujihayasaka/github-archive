import {buildFieldMetricsQueryKey} from '../../../../client/state-providers/memex-items/queries/query-keys'
import type {
  FieldMetricsQueryData,
  PaginatedMemexItemsQueryVariables,
} from '../../../../client/state-providers/memex-items/queries/types'
import {mergeFieldMetricsQueryData} from '../../../../client/state-providers/memex-items/query-client-api/field-metrics'
import {initQueryClient} from './helpers'

describe('query-client-api field metrics', () => {
  describe('mergeFieldMetricsQueryData', () => {
    it('updates query data if empty', () => {
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {q: 'test'}
      const newQueryData: FieldMetricsQueryData = {groups: {group1: [{fieldId: 123, value: 25}]}}

      mergeFieldMetricsQueryData(queryClient, variables, newQueryData)

      const queryKey = buildFieldMetricsQueryKey(variables)
      const queryDataFromClient = queryClient.getQueryData<FieldMetricsQueryData>(queryKey)
      expect(queryDataFromClient).toEqual(newQueryData)
    })

    it('merges new query data with existing, when no group ids overlap', () => {
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {q: 'test'}
      const initialQueryData: FieldMetricsQueryData = {groups: {group1: [{fieldId: 123, value: 25}]}}
      queryClient.setQueryData(buildFieldMetricsQueryKey(variables), initialQueryData)
      const newQueryData: FieldMetricsQueryData = {groups: {group2: [{fieldId: 123, value: 50}]}}

      mergeFieldMetricsQueryData(queryClient, variables, newQueryData)

      const expectedQueryData: FieldMetricsQueryData = {
        groups: {group1: [{fieldId: 123, value: 25}], group2: [{fieldId: 123, value: 50}]},
      }

      const queryKey = buildFieldMetricsQueryKey(variables)
      const queryDataFromClient = queryClient.getQueryData<FieldMetricsQueryData>(queryKey)
      expect(queryDataFromClient).toEqual(expectedQueryData)
    })

    it('merges new query data with existing, when group ids overlap', () => {
      const queryClient = initQueryClient()
      const variables: PaginatedMemexItemsQueryVariables = {q: 'test'}
      const initialQueryData: FieldMetricsQueryData = {groups: {group1: [{fieldId: 123, value: 25}]}}
      queryClient.setQueryData(buildFieldMetricsQueryKey(variables), initialQueryData)
      const newQueryData: FieldMetricsQueryData = {
        groups: {group1: [{fieldId: 123, value: 40}], group2: [{fieldId: 123, value: 50}]},
      }

      mergeFieldMetricsQueryData(queryClient, variables, newQueryData)

      const expectedQueryData: FieldMetricsQueryData = {
        groups: {group1: [{fieldId: 123, value: 40}], group2: [{fieldId: 123, value: 50}]},
      }

      const queryKey = buildFieldMetricsQueryKey(variables)
      const queryDataFromClient = queryClient.getQueryData<FieldMetricsQueryData>(queryKey)
      expect(queryDataFromClient).toEqual(expectedQueryData)
    })
  })
})
