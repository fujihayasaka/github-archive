export const formatCommandDuration = (startDate: Date | null, endDate: Date | null): string => {
  if (!startDate || !endDate) return ''

  const msInSecond = 1000
  const msInMinute = 60 * msInSecond
  const msInHour = 60 * msInMinute
  const msInDay = 24 * msInHour

  let delta = Math.abs(endDate.getTime() - startDate.getTime())

  const days = Math.floor(delta / msInDay)
  delta -= days * msInDay
  const hours = Math.floor(delta / msInHour)
  delta -= hours * msInHour
  const minutes = Math.floor(delta / msInMinute)
  delta -= minutes * msInMinute
  const seconds = Math.floor(delta / msInSecond)

  const parts = []
  if (days > 0) parts.push(`${days}d`)
  if (hours > 0) parts.push(`${hours}h`)
  if (minutes > 0) parts.push(`${minutes}m`)
  if (seconds > 0) parts.push(`${seconds}s`)

  return parts.join(' ')
}
