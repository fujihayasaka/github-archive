import {UsagePeriod} from '../enums'
import type {PeriodSelection} from '../types/usage'

/**
 * @param usageAt usage date formatted as YYYY-MM-DDTHH:MM:SS.MMMZ UTC, ex: 2023-03-14T16:21:25.316Z
 * @returns formatted date string
 * UsagePeriod.TODAY: H (4 PM)
 * UsagePeriod.THIS_MONTH: M/D/YYYY (3/14/2023)
 * UsagePeriod.THIS_YEAR: MMM YYYY (Mar 2023)
 */
export const formatUsageDateForPeriod = (usageAt: string | number, period: UsagePeriod | undefined): string => {
  const date = new Date(usageAt)
  switch (period) {
    case UsagePeriod.TODAY:
      return date.toLocaleTimeString('default', {timeZone: 'UTC', hour: 'numeric'})
    case UsagePeriod.THIS_MONTH:
    case UsagePeriod.LAST_MONTH:
      return date.toLocaleDateString('default', {timeZone: 'UTC', month: 'short', day: 'numeric', year: 'numeric'})
    case UsagePeriod.THIS_YEAR:
    case UsagePeriod.LAST_YEAR: {
      const month = date.toLocaleDateString('default', {timeZone: 'UTC', month: 'short'})
      const year = date.getUTCFullYear()
      return `${month} ${year}`
    }
    default:
      return date.toLocaleDateString('default', {timeZone: 'UTC', month: 'short', day: 'numeric', year: 'numeric'})
  }
}

//
// returns MMM YYYY (Mar 2023) if day is not present
export const formatDate = (year: number, month: number, day?: number): string => {
  const date = new Date(year, month - 1, day ?? 1)

  const monthName = getMonthName(month, 'short')
  const yearName = date.getFullYear()

  if (day) {
    return date.toLocaleDateString('default', {timeZone: 'UTC', month: 'short', day: 'numeric', year: 'numeric'})
  } else {
    return `${monthName} ${yearName}`
  }
}

const getMonthName = (monthNumber: number, fmt: 'long' | 'short' = 'long'): string => {
  const date = new Date()
  date.setMonth(monthNumber - 1)

  return date.toLocaleString('default', {month: fmt})
}

export function getDateString(range: {from: Date; to: Date}) {
  // en-CA formats the date as YYYY-MM-DD, which is what the usage report API expects
  return {
    startDate: range.from.toLocaleDateString('en-CA'),
    endDate: range.to.toLocaleDateString('en-CA'),
  }
}

export function getPeriodText(period?: PeriodSelection) {
  if (!period) return ''

  switch (period?.type) {
    case UsagePeriod.THIS_YEAR: {
      const date = new Date()
      return date.toLocaleDateString('en-US', {timeZone: 'UTC', year: 'numeric'})
    }
    case UsagePeriod.THIS_MONTH: {
      const date = new Date()

      const month = date.toLocaleDateString('en-US', {timeZone: 'UTC', month: 'short'})
      const firstDay = new Date(date.getFullYear(), date.getMonth(), 1).getDate()
      const lastDay = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate()

      return `${month} ${firstDay} - ${month} ${lastDay}, ${date.getFullYear()}`
    }
    case UsagePeriod.TODAY: {
      const date = new Date()
      const dateString = date.toLocaleDateString('en-US', {
        timeZone: 'UTC',
        month: 'long',
        day: 'numeric',
        year: 'numeric',
      })
      return `${dateString} (All times in UTC)`
    }
    case UsagePeriod.LAST_MONTH: {
      const date = new Date()
      date.setMonth(date.getMonth() - 1)
      const month = date.toLocaleDateString('en-US', {timeZone: 'UTC', month: 'short'})
      const firstDay = new Date(date.getFullYear(), date.getMonth(), 1).getDate()
      const lastDay = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate()

      return `${month} ${firstDay} - ${month} ${lastDay}, ${date.getFullYear()}`
    }
    case UsagePeriod.LAST_YEAR: {
      const date = new Date()
      const year = date.toLocaleDateString('en-US', {timeZone: 'UTC', year: 'numeric'})
      return `${Number(year) - 1} (All times in UTC)`
    }
    default: {
      return ''
    }
  }
}
