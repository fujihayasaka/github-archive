import type {Week} from '../repos-contributors-chart-types'
import type {RangeSelectionContextValues} from '../contexts/RangeSelectionContext'

type getWeekRangeIndicesProps = {
  weeks: Array<Pick<Week, 'week'>>
  rangeSelection?: Omit<RangeSelectionContextValues, 'setDate'>
}

type Result = {
  from: number
  to: number
}

export function getWeekRangeIndices({weeks, rangeSelection}: getWeekRangeIndicesProps): Result {
  const to = rangeSelection?.to ?? Date.now()
  if (!rangeSelection || !rangeSelection.from || !to) {
    return {
      from: 0,
      to: weeks.length - 1,
    }
  }

  const startIndex = weeks.findIndex(({week}) => week >= (rangeSelection.from || 0))
  const reverseEndIndex = [...weeks].reverse().findIndex(({week}) => week <= to)

  // range is outside of available weeks
  if ((startIndex === 0 && reverseEndIndex === -1) || (startIndex === -1 && reverseEndIndex === 0)) {
    return {
      from: 0,
      to: weeks.length - 1,
    }
  }

  return {
    from: startIndex,
    to: weeks.length - 1 - reverseEndIndex,
  }
}
