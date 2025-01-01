import type {DateRange} from '../../../common/utils/date-period'

export function calculatePreviousTwoDays(startDate: string): DateRange {
  const newStartDate = new Date(startDate)
  const newEndDate = new Date(startDate)

  newStartDate.setDate(newStartDate.getDate() - 2)
  newEndDate.setDate(newEndDate.getDate() - 1)

  const newStartDateString = newStartDate.toISOString().split('T')[0]
  const newEndDateString = newEndDate.toISOString().split('T')[0]

  return {startDate: newStartDateString || '', endDate: newEndDateString || ''}
}
