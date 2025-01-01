import {memo, useCallback, useMemo} from 'react'

import {getDecimalPlaces} from '../../utils/math'
import {MemexColumnDataType} from '../api/columns/contracts/memex-column'
import type {NumericValue} from '../api/columns/contracts/number'
import type {FieldOperation} from '../api/view/contracts'
import {AggregationSettingsContext, type FieldAggregate} from '../hooks/use-aggregation-settings'
import {ViewStateActionTypes} from '../hooks/use-view-state-reducer/view-state-action-types'
import {useViews} from '../hooks/use-views'
import type {ColumnModel} from '../models/column-model'
import type {MemexItemModel} from '../models/memex-item-model'
import {useAllColumns} from '../state-providers/columns/use-all-columns'
import type {GroupId} from '../state-providers/memex-items/queries/query-keys'
import {useFieldMetricsQuery} from '../state-providers/memex-items/queries/use-field-metrics-query'

export const AggregationSettingsProvider = memo<{
  children?: React.ReactNode
}>(function AggregationSettingsProvider({children}) {
  const {currentView, viewStateDispatch} = useViews()
  const {allColumns} = useAllColumns()

  const addFieldAggregation = useCallback(
    (viewNumber: number, fieldOperation: FieldOperation, column: ColumnModel): void => {
      viewStateDispatch({type: ViewStateActionTypes.AddFieldAggregation, viewNumber, fieldOperation, column})
    },
    [viewStateDispatch],
  )

  const removeFieldAggregation = useCallback(
    (viewNumber: number, fieldOperation: FieldOperation, column: ColumnModel): void => {
      viewStateDispatch({type: ViewStateActionTypes.RemoveFieldAggregation, viewNumber, fieldOperation, column})
    },
    [viewStateDispatch],
  )

  const toggleItemsCount = useCallback(
    (viewNumber: number): void => {
      viewStateDispatch({type: ViewStateActionTypes.ToggleItemsCount, viewNumber})
    },
    [viewStateDispatch],
  )

  const fieldMetricsQuery = useFieldMetricsQuery()
  const fieldMetricsData = fieldMetricsQuery?.data

  const getAggregatesForItems = useCallback(
    (items: Readonly<Array<Pick<MemexItemModel, 'columns'>>>) => {
      const columnAggregates = []
      const numericFields = allColumns.filter(c => c.dataType === MemexColumnDataType.Number).map(c => c.id)

      const map: {[key: string]: number} = {}
      for (const field of currentView?.localViewStateDeserialized.aggregationSettings.sum ?? []) {
        const aggregate = {
          name: field.name,
          sum: 0,
          maxDecimalPlaces: 0,
        }

        for (const item of items) {
          const columnData = item.columns
          const number = columnData[field.id] as NumericValue
          // @ts-expect-error This is not statically known as a number in newer versions of typescript, we should validate it
          const index = numericFields.indexOf(field.id)
          map[field.name] = index

          aggregate.sum += number?.value ?? 0
          aggregate.maxDecimalPlaces = Math.max(aggregate.maxDecimalPlaces, getDecimalPlaces(number?.value ?? 0))
        }
        columnAggregates.push(aggregate)
      }
      return columnAggregates.sort((a, b) => (map[a.name] ?? 0) - (map[b.name] ?? 0))
    },
    [currentView?.localViewStateDeserialized.aggregationSettings.sum, allColumns],
  )

  const getAggregatesForGroupId = useCallback(
    (groupId: GroupId) => {
      const fieldAggregates: Array<FieldAggregate> = []
      const fieldMetricsForGroupId = fieldMetricsData?.groups[groupId]

      if (fieldMetricsForGroupId) {
        for (const fieldMetric of fieldMetricsForGroupId) {
          const field = currentView?.localViewStateDeserialized.aggregationSettings.sum?.find(
            f => f.id === fieldMetric.fieldId,
          )

          if (field) {
            const aggregate = {
              name: field.name,
              sum: fieldMetric.value,
              maxDecimalPlaces: getDecimalPlaces(fieldMetric.value),
            }
            fieldAggregates.push(aggregate)
          }
        }
      }
      return fieldAggregates
    },
    [currentView?.localViewStateDeserialized.aggregationSettings.sum, fieldMetricsData?.groups],
  )

  return (
    <AggregationSettingsContext.Provider
      value={useMemo(() => {
        return {
          hideItemsCount: !!currentView?.localViewStateDeserialized.aggregationSettings.hideItemsCount,
          sum: currentView?.localViewStateDeserialized.aggregationSettings.sum ?? [],
          toggleItemsCount,
          addFieldAggregation,
          removeFieldAggregation,
          isAggregationSettingsDirty: currentView?.isAggregationSettingsDirty ?? false,
          getAggregatesForItems,
          getAggregatesForGroupId,
        }
      }, [
        currentView?.localViewStateDeserialized.aggregationSettings.hideItemsCount,
        currentView?.localViewStateDeserialized.aggregationSettings.sum,
        currentView?.isAggregationSettingsDirty,
        toggleItemsCount,
        addFieldAggregation,
        removeFieldAggregation,
        getAggregatesForGroupId,
        getAggregatesForItems,
      ])}
    >
      {children}
    </AggregationSettingsContext.Provider>
  )
})
