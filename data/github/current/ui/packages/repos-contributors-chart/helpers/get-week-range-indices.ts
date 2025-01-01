import type {OptionalRangeSelection, Week} from '../repos-contributors-chart-types'

type getWeekRangeIndicesProps = {
  weeks: Array<Pick<Week, 'date'>>
  rangeSelection?: OptionalRangeSelection
}

type Result = {
  from: number
  to: number
}

export function getWeekRangeIndices({weeks, rangeSelection}: getWeekRangeIndicesProps): Result {
  const to = rangeSelection?.to || new Date()

  if (!rangeSelection || isNaN(rangeSelection.from.getTime()) || isNaN(to.getTime())) {
    return {
      from: 0,
      to: weeks.length - 1,
    }
  }

  const startIndex = weeks.findIndex(({date}) => date >= rangeSelection.from)
  const reverseEndIndex = [...weeks].reverse().findIndex(({date}) => date <= to)

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
