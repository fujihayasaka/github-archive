import {format, parseISO} from 'date-fns'

export function rollingDateRangeString(startDate: string, endDate: string): string {
  const startDateISO = parseISO(startDate)
  const endDateISO = parseISO(endDate)
  const isDifferentYear = startDateISO.getFullYear() !== endDateISO.getFullYear()
  const startDateTemplate = isDifferentYear ? 'MMM dd, yyyy' : 'MMM dd'

  return `${format(startDateISO, startDateTemplate)} - ${format(endDateISO, 'MMM dd, yyyy')}`
}

export function fullDateRangeString(startDate: string, endDate: string): string {
  const startDateISO = parseISO(startDate)
  const endDateISO = parseISO(endDate)

  return `${format(startDateISO, 'MMM dd, yyyy')} - ${format(endDateISO, 'MMM dd, yyyy')}`
}
