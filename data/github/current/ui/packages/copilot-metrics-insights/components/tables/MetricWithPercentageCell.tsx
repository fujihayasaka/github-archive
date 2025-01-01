export interface Props {
  metric: number
  total: number
}

export function MetricWithPercentageCell({metric, total}: Props) {
  if (total === 0) {
    return <span>0</span>
  }
  const percentage = Math.round((metric / total) * 100)

  return (
    <span>
      {metric} ({percentage}%)
    </span>
  )
}
