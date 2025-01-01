export function calculateElapsedTime(createdAt: Date | string, completedAt?: Date | string): string {
  const created = new Date(createdAt).getTime()
  // Temporary fix for handling the case when completedAt is not set in CAPI. Remove once CAPI is updated.
  const defaultCAPIDate = '0001-01-01T00:00:00Z'
  const nowOrCompleted = completedAt && completedAt !== defaultCAPIDate ? new Date(completedAt).getTime() : Date.now()
  const diffInSeconds = Math.floor((nowOrCompleted - created) / 1000)

  const days = Math.floor(diffInSeconds / (60 * 60 * 24))
  const hours = Math.floor((diffInSeconds % (60 * 60 * 24)) / (60 * 60))
  const minutes = Math.floor((diffInSeconds % (60 * 60)) / 60)
  const seconds = diffInSeconds % 60

  // Create an array of intervals with their labels
  const intervals = [
    {value: days, label: 'd'},
    {value: hours, label: 'h'},
    {value: minutes, label: 'm'},
    {value: seconds, label: 's'},
  ]

  // Filter out intervals with a value of 0
  const nonZeroIntervals = intervals.filter(interval => interval.value > 0)

  // Return the two largest non-zero intervals
  if (nonZeroIntervals.length === 0) return '0s'
  if (nonZeroIntervals.length === 1) return `${nonZeroIntervals[0]?.value ?? 0}${nonZeroIntervals[0]?.label ?? ''}`
  return nonZeroIntervals[1]
    ? `${nonZeroIntervals[0]?.value}${nonZeroIntervals[0]?.label} ${nonZeroIntervals[1].value}${
        nonZeroIntervals[1].label ?? ''
      }`
    : `${nonZeroIntervals[0]?.value ?? 0}${nonZeroIntervals[0]?.label ?? ''}`
}
