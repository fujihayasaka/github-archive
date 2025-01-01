import type {IndexPayload} from '../routes/Index'
import type {AggregateDataPoint} from '../types'

export function getIndexRoutePayload(): IndexPayload {
  return {
    graphDataPath: '/',
    isUsingContributionInsights: false,
    tooLargeUrl: '/',
  }
}

export function getAggregateData(): AggregateDataPoint[] {
  const dataPoints: AggregateDataPoint[] = []

  const today = new Date()
  const years = 3
  for (let i = 0; i < 52 * years; i++) {
    // Calculate the date for the current iteration
    const date = new Date(today)
    date.setDate(date.getDate() - i * 7)
    // Subtract i weeks (7 days per week)

    const addition = Math.floor(Math.random() * 40)
    const deletion = Math.floor(Math.random() * -40)
    dataPoints.push([date.getTime() / 1000, addition, deletion])
  }
  return dataPoints.reverse()
}
