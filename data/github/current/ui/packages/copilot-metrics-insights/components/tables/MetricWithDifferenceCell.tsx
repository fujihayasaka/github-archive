type Props = {
  average: number
  percentDifference: number
  hourSuffix?: boolean
}

export function MetricWithDifferenceCell({average, percentDifference, hourSuffix}: Props) {
  const suffix = hourSuffix ? 'h' : ''
  return (
    <div className="d-flex flex-column">
      <span>
        {average}
        {suffix}{' '}
        <span>
          (<span>{percentDifference >= 0 ? '+' : '-'}</span>
          {Math.round(Math.abs(percentDifference) * 100)}%)
        </span>
      </span>
    </div>
  )
}
