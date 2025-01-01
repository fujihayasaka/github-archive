import type {ColorCodingConfig} from '@github-ui/insights-charts'
import {colors as primerColors, colorScale, getTheme, simpleTheme} from '@github-ui/insights-charts'
import {eachDayOfInterval, format, isBefore, isSameDay, min, subDays, subMonths} from 'date-fns'

import type {
  MemexChartConfiguration,
  MemexChartOperation,
  MemexChartTimePeriod,
  MemexChartType,
} from '../../api/charts/contracts/api'
import {PullRequestState, StateReason} from '../../api/common-contracts'
import {ItemType} from '../../api/memex-items/item-type'
import getInsightsColumnValues from '../../helpers/insights-column-values'
import {not_typesafe_nonNullAssertion} from '../../helpers/non-null-assertion'
import {isNumber} from '../../helpers/parsing'
import type {ColumnModel} from '../../models/column-model'
import type {MemexItemModel} from '../../models/memex-item-model'
import {styleForChartType} from '../../pages/insights/highcharts-theme'
import {useFindColumnByDatabaseId} from '../columns/use-find-column-by-database-id'
import {useMemexItems} from '../memex-items/use-memex-items'
import {applyMemexChartOperation} from './chart-helpers'

const DATE_FORMAT = 'yyyy-MM-dd'

// mimics the way the default chart colors are generated in the insights-charts package
// but allows us to configure them for each grouping (Open, Completed, Not planned)
export function getLeanInsightsColorCoding(): ColorCodingConfig | undefined {
  const theme = getTheme()
  const primerScaleColors = primerColors[simpleTheme(theme)].scale
  const greenBorder = primerScaleColors.green[colorScale(theme, 4, 5)]
  const greenBackground = primerScaleColors.green[colorScale(theme, 0, 9)]
  const purpleBorder = primerScaleColors.purple[colorScale(theme, 5, 5)]
  const purpleBackground = primerScaleColors.purple[colorScale(theme, 0, 9)]
  const redBorder = primerScaleColors.red[colorScale(theme, 4, 5)]
  const redBackground = primerScaleColors.red[colorScale(theme, 0, 9)]
  const grayBorder = primerScaleColors.gray[colorScale(theme, 6, 4)]
  const grayBackground = primerScaleColors.gray[colorScale(theme, 0, 7)]

  // if somehow none of these colors are defined, return undefined and use the default color coding
  if (
    greenBorder === undefined ||
    greenBackground === undefined ||
    purpleBorder === undefined ||
    purpleBackground === undefined ||
    redBorder === undefined ||
    redBackground === undefined ||
    grayBorder === undefined ||
    grayBackground === undefined
  ) {
    return undefined
  }

  return {
    [LeanHistoricalStateType.OPEN]: {
      borderColor: greenBorder,
      backgroundColor: greenBackground,
    },
    [LeanHistoricalStateType.COMPLETED]: {
      borderColor: purpleBorder,
      backgroundColor: purpleBackground,
    },
    [LeanHistoricalStateType.CLOSED]: {
      borderColor: redBorder,
      backgroundColor: redBackground,
    },
    [LeanHistoricalStateType.NOT_PLANNED]: {
      borderColor: grayBorder,
      backgroundColor: grayBackground,
    },
    [LeanHistoricalStateType.DUPLICATE]: {
      borderColor: grayBorder,
      backgroundColor: grayBackground,
    },
  }
}

export const LeanHistoricalStateType = {
  OPEN: 'Open', // open issues & prs
  COMPLETED: 'Completed', // completed issues and merged prs
  CLOSED: 'Closed pull requests', // closed prs
  NOT_PLANNED: 'Not planned', // not-planned issues
  DUPLICATE: 'Duplicate', // duplicated issues
} as const
export type LeanHistoricalStateType = (typeof LeanHistoricalStateType)[keyof typeof LeanHistoricalStateType]

type AccType = {
  series: Array<{name: string; data: Array<number>; color?: string; fillColor?: string; index: number}>
  xCoordinates: Array<string>
  OPEN: number
  COMPLETED: number
  CLOSED: number
  NOT_PLANNED: number
  DUPLICATE: number
}

// safely convert a date string to Date
function toDate(dateString?: string) {
  return dateString ? new Date(dateString) : undefined
}

// get createdAt dateString from draft issues, issues & PRs
function getIssueCreatedAt(item: MemexItemModel) {
  if (item.issueCreatedAt) {
    return item.issueCreatedAt
  } else if (item.contentType === 'DraftIssue') {
    return item.createdAt
  }
}

// returns a list of dates used to build the chart x-axis, based on the period
export function getDaysFromPeriod({
  period,
  startDate,
  endDate,
  items,
}: {
  period: MemexChartTimePeriod
  startDate?: string
  endDate?: string
  items: Readonly<Array<MemexItemModel>>
}): Array<Date> {
  const now = new Date()

  switch (period) {
    case '2W':
      return eachDayOfInterval({
        start: subDays(now, 14),
        end: now,
      })
    case '1M':
      return eachDayOfInterval({
        start: subMonths(now, 1),
        end: now,
      })
    case '3M':
      return eachDayOfInterval({
        start: subMonths(now, 3),
        end: now,
      })
    case 'max': {
      const firstDate = min(
        items.map(item => {
          const createdAt = getIssueCreatedAt(item)

          return createdAt ? new Date(createdAt) : now
        }),
      )
      const oneWeekAgo = subDays(now, 7)

      return eachDayOfInterval({
        // makes the minimum max period 1 week
        start: isBefore(firstDate, oneWeekAgo) ? firstDate : oneWeekAgo,
        end: now,
      })
    }
    case 'custom':
      return eachDayOfInterval({
        start: startDate ? new Date(startDate) : now,
        end: endDate ? new Date(endDate) : now,
      })
  }
}

// coverts a date string to a date key keyed by yyyy-MM-dd
function getDateKey(dateString?: string) {
  if (!dateString) return ''

  return format(new Date(dateString), DATE_FORMAT).toString()
}

// check if a PR is merged
function isPullRequestMerged(item: MemexItemModel) {
  const columnValue = item.columns?.Title

  return columnValue?.contentType === ItemType.PullRequest && columnValue.value.state === PullRequestState.Merged
}

// get the state map for the given item based on the contentType, stateReason and merged state
function getClosedStateMap(
  item: MemexItemModel,
  closedStateMap: {
    completed: Map<string, number>
    closed: Map<string, number>
    notPlanned: Map<string, number>
    duplicate: Map<string, number>
  },
) {
  // if it's an issue
  if (item.contentType === ItemType.Issue) {
    if (item.stateReason === StateReason.NotPlanned) {
      return closedStateMap.notPlanned
    } else if (item.stateReason === StateReason.Duplicate) {
      return closedStateMap.duplicate
    } else {
      // otherwise it's completed
      return closedStateMap.completed
    }
    // if it's a PR
  } else {
    if (isPullRequestMerged(item)) {
      return closedStateMap.completed
    } else {
      return closedStateMap.closed
    }
  }
}

function getInitialCount({items, dates}: {items: Readonly<Array<MemexItemModel>>; dates: Array<Date>}) {
  const startDate = min(dates)

  return items.reduce(
    (acc, item) => {
      const createdAt = getIssueCreatedAt(item)

      if (createdAt && isBefore(new Date(createdAt), startDate)) {
        acc.open++
      }

      if (item.issueClosedAt && isBefore(new Date(item.issueClosedAt), startDate)) {
        // if its a closed issue
        if (item.contentType === ItemType.Issue) {
          if (item.stateReason === StateReason.NotPlanned) {
            acc.notPlanned++
          } else if (item.stateReason === StateReason.Duplicate) {
            acc.duplicate++
          } else {
            acc.completed++
          }
          acc.open--
          // if it's a closed PR
        } else if (item.contentType === ItemType.PullRequest) {
          if (isPullRequestMerged(item)) {
            acc.completed++
          } else {
            acc.closed++ // if it's not a merged PR, it's closed
          }
          acc.open--
        }
      }

      return acc
    },
    {
      open: 0,
      completed: 0,
      closed: 0,
      notPlanned: 0,
      duplicate: 0,
    },
  )
}
function getMapofDatesByKey({items}: {items: Readonly<Array<MemexItemModel>>}) {
  return items.reduce(
    (acc, item) => {
      const createdAt = getIssueCreatedAt(item)
      const createdAtKey = getDateKey(createdAt)

      if (!createdAtKey) return acc

      if (acc.open.get(createdAtKey)) {
        acc.open.set(createdAtKey, (acc.open.get(createdAtKey) || 0) + 1)
      } else {
        acc.open.set(createdAtKey, 1)
      }

      const closedAtKey = getDateKey(item.issueClosedAt)
      const closedMap = getClosedStateMap(item, acc)

      if (!closedAtKey) return acc

      if (closedMap.get(closedAtKey)) {
        closedMap.set(closedAtKey, (closedMap.get(closedAtKey) || 0) + 1)
      } else {
        closedMap.set(closedAtKey, 1)
      }

      return acc
    },
    {
      open: new Map<string, number>(),
      completed: new Map<string, number>(),
      closed: new Map<string, number>(),
      notPlanned: new Map<string, number>(),
      duplicate: new Map<string, number>(),
    },
  )
}

function setSeries(acc: AccType, key: keyof typeof LeanHistoricalStateType, type: MemexChartType) {
  const state = LeanHistoricalStateType[key]
  const colorSet = getLeanInsightsColorCoding()?.[state]
  const keyData = acc.series.find(s => s.name === state)
  const style = colorSet ? styleForChartType(type, colorSet) : {}
  if (keyData === undefined) {
    acc.series.push({
      name: state,
      data: [acc[key]],
      index: getStateChartCardSortValue(state),
      ...style,
    })
  } else {
    keyData.data.push(acc[key])
  }
}

function getSeriesRowsChartCard({
  items,
  dates,
  type,
}: {
  items: Readonly<Array<MemexItemModel>>
  dates: Array<Date>
  type: MemexChartType
}) {
  const initialSeries: Array<{name: string; data: Array<number>; index: number}> = []
  if (items.length) {
    // count the initial number of open, closed and not-planned issues
    const initialCounts = getInitialCount({items, dates})

    // returns a map for each state reason grouping (open, closed, not planned), keyed by a dateKey ('yyyy-MM-dd')
    const countByDateMap = getMapofDatesByKey({items})

    const {series, xCoordinates} = dates.reduce(
      (acc, day) => {
        const key = format(day, DATE_FORMAT).toString()
        const openCount = countByDateMap.open.get(key) || 0
        const completedCount = countByDateMap.completed.get(key) || 0
        const closedCount = countByDateMap.closed.get(key) || 0
        const notPlannedCount = countByDateMap.notPlanned.get(key) || 0
        const duplicateCount = countByDateMap.duplicate.get(key) || 0

        acc.OPEN = acc.OPEN + openCount - completedCount - closedCount - notPlannedCount - duplicateCount
        acc.COMPLETED += completedCount
        acc.CLOSED += closedCount
        acc.NOT_PLANNED += notPlannedCount
        acc.DUPLICATE += duplicateCount

        acc.xCoordinates.push(format(day, 'MMM d'))
        if (countByDateMap.notPlanned.size > 0) {
          setSeries(acc, 'NOT_PLANNED', type)
        }
        if (countByDateMap.duplicate.size > 0) {
          setSeries(acc, 'DUPLICATE', type)
        }
        if (countByDateMap.closed.size > 0) {
          setSeries(acc, 'CLOSED', type)
        }
        if (countByDateMap.completed.size > 0) {
          setSeries(acc, 'COMPLETED', type)
        }
        if (countByDateMap.open.size + initialCounts.open > 0) {
          setSeries(acc, 'OPEN', type)
        }
        return acc
      },

      // initial counts are used to calculate the open, closed and not planned counts for the first date
      // but we only care about the total number of currently open issues
      {
        series: initialSeries,
        xCoordinates: [] as Array<string>,
        OPEN: initialCounts.open,
        COMPLETED: 0,
        CLOSED: 0,
        NOT_PLANNED: 0,
        DUPLICATE: 0,
      },
    )
    return {series, xCoordinates}
  }

  return {series: [], xCoordinates: []}
}

// returns the state (open/completed/closed/not-planned) of the item on the given date
function getItemStateByKey({item, date, startDate}: {item: MemexItemModel; date: Date; startDate: Date}) {
  const createdAt = getIssueCreatedAt(item)
  const createdAtDate = toDate(createdAt)
  const closedAtDate = toDate(item.issueClosedAt)
  // if the item was closed before the date, it's not-planned or complete
  if (closedAtDate && (isBefore(closedAtDate, date) || isSameDay(closedAtDate, date))) {
    // don't count items that didn't transition before the startDate
    if (isBefore(closedAtDate, startDate)) {
      return undefined
    }
    if (item.contentType === ItemType.Issue) {
      if (item.stateReason === StateReason.NotPlanned) {
        return LeanHistoricalStateType.NOT_PLANNED
      } else if (item.stateReason === StateReason.Duplicate) {
        return LeanHistoricalStateType.DUPLICATE
      } else {
        return LeanHistoricalStateType.COMPLETED
      }
    } else if (item.contentType === ItemType.PullRequest) {
      if (isPullRequestMerged(item)) {
        return LeanHistoricalStateType.COMPLETED
      } else {
        return LeanHistoricalStateType.CLOSED
      }
    } else {
      return undefined
    }
  }

  // if the item was created before the date, it's open
  if (createdAtDate && (isBefore(createdAtDate, date) || isSameDay(createdAtDate, date))) {
    return LeanHistoricalStateType.OPEN
  }

  return undefined
}

// used to sort rows by state (Open => Completed => Not Planned)
function getStateChartCardSortValue(state?: string) {
  switch (state) {
    case LeanHistoricalStateType.OPEN:
      return 0
    case LeanHistoricalStateType.COMPLETED:
      return 1
    case LeanHistoricalStateType.CLOSED:
      return 2
    case LeanHistoricalStateType.NOT_PLANNED:
      return 3
    case LeanHistoricalStateType.DUPLICATE:
      return 4
    default:
      return 5
  }
}

function getSeriesRowsByOperationChartCard({
  items,
  dates,
  yAxisColumnModel,
  memexChartOperation,
}: {
  items: Readonly<Array<MemexItemModel>>
  dates: Array<Date>
  yAxisColumnModel: ColumnModel
  memexChartOperation: MemexChartOperation
}) {
  const startDate = min(dates)
  const valueByItemIdMap = new Map<number, number>()
  // DateKey:Map => State:Map => ItemIds:Set
  const itemIdsByDateMap = new Map<string, Map<LeanHistoricalStateType, Set<number>>>(
    dates.map(date => [
      getDateKey(date.toISOString()),
      new Map([
        [LeanHistoricalStateType.NOT_PLANNED, new Set<number>()],
        [LeanHistoricalStateType.DUPLICATE, new Set<number>()],
        [LeanHistoricalStateType.COMPLETED, new Set<number>()],
        [LeanHistoricalStateType.CLOSED, new Set<number>()],
        [LeanHistoricalStateType.OPEN, new Set<number>()],
      ]),
    ]),
  )

  const emptyStateSet = new Set<LeanHistoricalStateType>([
    LeanHistoricalStateType.NOT_PLANNED,
    LeanHistoricalStateType.DUPLICATE,
    LeanHistoricalStateType.COMPLETED,
    LeanHistoricalStateType.CLOSED,
    LeanHistoricalStateType.OPEN,
  ])

  for (const item of items) {
    const columnData = item.columns
    // currently we only support one yAxisValue, eg: Estimate
    const yAxisValue = parseFloat(
      not_typesafe_nonNullAssertion(getInsightsColumnValues(yAxisColumnModel, columnData)[0]),
    )
    valueByItemIdMap.set(item.id, yAxisValue)

    for (const date of dates) {
      const key = getDateKey(date.toISOString())
      const state = getItemStateByKey({item, date, startDate})
      if (state) {
        itemIdsByDateMap.get(key)?.get(state)?.add(item.id)
        emptyStateSet.delete(state)
      }
    }
  }

  const xCoordinates: Array<string> = []
  const series: Array<{name: string; data: Array<number>; color?: string; fillColor?: string; index: number}> = []

  // iterate through the Map and creates the rows
  for (const [dateKey, itemIdsByStateMap] of itemIdsByDateMap) {
    xCoordinates.push(dateKey)
    for (const [state, itemIdSet] of itemIdsByStateMap) {
      const itemIds = Array.from(itemIdSet)
      const value = applyMemexChartOperation({
        memexChartOperation,
        values: itemIds.map(itemId => valueByItemIdMap.get(itemId) || 0),
      })
      // create a row only if there are items for the given date and state
      if (!emptyStateSet.has(state)) {
        const keyData = series.find(s => s.name === state)
        if (keyData === undefined) {
          const colorSet = getLeanInsightsColorCoding()?.[state]
          series.push({
            name: state,
            data: [value || 0],
            fillColor: colorSet?.backgroundColor,
            color: colorSet?.borderColor,
            index: getStateChartCardSortValue(state),
          })
        } else {
          keyData.data.push(value || 0)
        }
      }
    }
  }

  // ensures expected order of rows
  return {series, xCoordinates}
}

/**
 * Memoization fails here since the observables from allItems and filteredItems
 * internal items aren't going to trigger a re-render, when they should.
 */
export function useLeanHistoricalChartSeriesChartCard({
  configuration,
  filteredItems,
  startDate,
  endDate,
}: {
  configuration: MemexChartConfiguration
  filteredItems: Readonly<Array<MemexItemModel>> | null
  startDate?: string
  endDate?: string
}) {
  const period = configuration.time?.period || '2W'
  const isLoading = false
  const {items: allItems} = useMemexItems()
  const {findColumnByDatabaseId} = useFindColumnByDatabaseId()
  const items = filteredItems ? filteredItems : allItems
  const daysFromPeriod = getDaysFromPeriod({period, startDate, endDate, items})
  const yAxisAggregate = configuration.yAxis.aggregate
  const yAxisOperationColumn = yAxisAggregate?.columns?.[0]
  const yAxisColumnModel = isNumber(yAxisOperationColumn) ? findColumnByDatabaseId(yAxisOperationColumn) : undefined
  const yAxisAggregateEnabled = yAxisAggregate.operation !== 'count' && yAxisColumnModel

  return yAxisAggregateEnabled
    ? {
        isLoading,
        ...getSeriesRowsByOperationChartCard({
          items,
          dates: daysFromPeriod,
          yAxisColumnModel,
          memexChartOperation: yAxisAggregate.operation,
        }),
      }
    : {
        isLoading,
        ...getSeriesRowsChartCard({items, dates: daysFromPeriod, type: configuration.type}),
      }
}
