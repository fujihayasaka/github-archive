import type {Week} from '../../repos-contributors-chart-types'
import {getWeekRangeIndices} from '../get-week-range-indices'

const weeks: Array<Pick<Week, 'date'>> = [
  {date: new Date('2022-01-01')},
  {date: new Date('2022-03-01')},
  {date: new Date('2022-05-01')},
  {date: new Date('2023-01-01')},
  {date: new Date('2023-03-01')},
  {date: new Date('2023-05-01')},
]

describe('getWeekRangeIndices', () => {
  test('returns all weeks if no range is selected', () => {
    const result = getWeekRangeIndices({weeks, rangeSelection: undefined})
    expect(result).toEqual({from: 0, to: 5})
  })
  test('returns weeks within the selected range when "to" is not provided', () => {
    const rangeSelection = {
      from: new Date('2022-02-01'),
    }
    const result = getWeekRangeIndices({weeks, rangeSelection})
    expect(result).toEqual({from: 1, to: 5})
  })
  test('returns weeks within the selected range', () => {
    const rangeSelection = {
      from: new Date('2022-02-01'),
      to: new Date('2023-02-01'),
    }
    const result = getWeekRangeIndices({weeks, rangeSelection})
    expect(result).toEqual({from: 1, to: 3})
  })
  test('returns all weeks if the selected range is outside the available range', () => {
    const rangeSelection = {
      from: new Date('2021-02-01'),
      to: new Date('2021-03-01'),
    }
    const result = getWeekRangeIndices({weeks, rangeSelection})
    expect(result).toEqual({from: 0, to: 5})
  })
  test('returns all weeks if the selected range is in the future', () => {
    const nextYear = new Date().getFullYear() + 1
    const rangeSelection = {
      from: new Date(`${nextYear}-02-01`),
    }
    const result = getWeekRangeIndices({weeks, rangeSelection})
    expect(result).toEqual({from: 0, to: 5})
  })
  test('returns all weeks if the selected range contains invalid dates', () => {
    const rangeSelection = {
      from: new Date('invalid'),
      to: new Date('invalid'),
    }
    const result = getWeekRangeIndices({weeks, rangeSelection})
    expect(result).toEqual({from: 0, to: 5})
  })
})
