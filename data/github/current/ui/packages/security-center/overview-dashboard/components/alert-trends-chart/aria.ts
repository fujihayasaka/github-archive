import {humanReadableDate} from '../../../common/utils/date-formatter'
import type {GroupingType} from './grouping-type'

/**
 * Generates an ARIA label for a line chart describing alert trends over time.
 */
export const generateAriaLabelForAlertTrends = (
  groupings: string[] | null,
  groupingType: GroupingType,
  startDate: string,
  endDate: string,
  isOpenSelected: boolean,
  isError?: boolean,
): string => {
  const state = isOpenSelected ? 'open' : 'closed'

  if (isError) {
    return `Empty chart. Alert trends could not be loaded right now.`
  } else if (groupings == null || !groupings.length) {
    return `Empty chart. There are no ${state} alerts in this period.`
  }

  const dateOptions = {includeYear: true}
  let groupingDescription = ''
  switch (groupingType) {
    case 'severity': {
      groupingDescription = `The y-axis shows counts of alerts with ${groupings.join(', ')} severities.`
      break
    }
    case 'age': {
      groupingDescription = getAvailableAges(groupings)
      break
    }
    case 'tool': {
      groupingDescription = `The y-axis shows counts of alerts grouped by ${groupings.join(', ')} tools.`
    }
  }

  const label = []
  label.push(`Line chart describing ${state} alert trends over time. It consists of ${groupings.length} time series.`)

  label.push(
    `The x-axis shows dates from ${humanReadableDate(
      new Date(Date.parse(startDate)),
      dateOptions,
    )} to ${humanReadableDate(new Date(Date.parse(endDate)), dateOptions)}.`,
  )

  if (groupings.length > 0) {
    label.push(groupingDescription)
  }

  label.push('This chart data can only be accessed as a table.')
  return label.join(' ')
}

function getAvailableAges(ages: string[]): string {
  const descriptiveAges = []
  if (ages.includes('< 30 days')) descriptiveAges.push('less than thirty days')
  if (ages.includes('31 - 59 days')) descriptiveAges.push('thirty-one to fifty-nine days')
  if (ages.includes('60 - 89 days')) descriptiveAges.push('sixty to eighty-nine days')
  if (ages.includes('90+ days')) descriptiveAges.push('ninety plus days')

  return `The y-axis shows counts of alert ages grouped by ${descriptiveAges.join(', ')}.`
}
