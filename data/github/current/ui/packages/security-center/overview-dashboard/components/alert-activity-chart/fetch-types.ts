export interface AlertActivityChartData {
  date: string
  endDate: string
  closed: number
  opened: number
}

export interface AlertActivityResult {
  data: AlertActivityChartData[]
}

export type AlertActivityData = {
  data: AlertActivityChartData[]
  sum: number
}
