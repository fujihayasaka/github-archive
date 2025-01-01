import {formatCommandDuration} from '../format-command-duration'

describe('formatCommandDuration', () => {
  it('should return an empty string if startDate is null', () => {
    const result = formatCommandDuration(null, new Date())
    expect(result).toBe('')
  })

  it('should return an empty string if endDate is null', () => {
    const result = formatCommandDuration(new Date(), null)
    expect(result).toBe('')
  })

  it('should return an empty string if both dates are null', () => {
    const result = formatCommandDuration(null, null)
    expect(result).toBe('')
  })

  it('should return the correct duration for a difference of 1 day', () => {
    const startDate = new Date('2025-01-01T00:00:00Z')
    const endDate = new Date('2025-01-02T00:00:00Z')
    const result = formatCommandDuration(startDate, endDate)
    expect(result).toBe('1d')
  })

  it('should return the correct duration for a difference of 1 hour', () => {
    const startDate = new Date('2025-01-01T00:00:00Z')
    const endDate = new Date('2025-01-01T01:00:00Z')
    const result = formatCommandDuration(startDate, endDate)
    expect(result).toBe('1h')
  })

  it('should return the correct duration for a difference of 1 minute', () => {
    const startDate = new Date('2025-01-01T00:00:00Z')
    const endDate = new Date('2025-01-01T00:01:00Z')
    const result = formatCommandDuration(startDate, endDate)
    expect(result).toBe('1m')
  })

  it('should return the correct duration for a difference of 1 second', () => {
    const startDate = new Date('2025-01-01T00:00:00Z')
    const endDate = new Date('2025-01-01T00:00:01Z')
    const result = formatCommandDuration(startDate, endDate)
    expect(result).toBe('1s')
  })

  it('should return the correct duration for a complex difference', () => {
    const startDate = new Date('2025-01-01T00:00:00Z')
    const endDate = new Date('2025-01-02T01:01:01Z')
    const result = formatCommandDuration(startDate, endDate)
    expect(result).toBe('1d 1h 1m 1s')
  })
})
