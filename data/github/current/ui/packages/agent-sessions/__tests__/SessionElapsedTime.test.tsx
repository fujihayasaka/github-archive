import {calculateElapsedTime} from '../utils/elapsed-time-util'

// Mock `Date.now` for consistent testing
const mockDateNow = jest.spyOn(Date, 'now')

describe('calculateElapsedTime', () => {
  it('should correctly calculate elapsed time showing the two largest non-zero intervals', () => {
    const createdAt = new Date('2025-03-01T00:00:00Z')
    const completedAt = new Date('2025-03-02T01:30:45Z')

    const elapsedTime = calculateElapsedTime(createdAt, completedAt)

    expect(elapsedTime).toBe('1d 1h') // Only the two largest non-zero intervals
  })

  it('should show only the largest interval if the second largest is zero', () => {
    const createdAt = new Date('2025-03-01T00:00:00Z')
    const completedAt = new Date('2025-03-01T02:00:00Z')

    const elapsedTime = calculateElapsedTime(createdAt, completedAt)

    expect(elapsedTime).toBe('2h') // Only the largest non-zero interval
  })

  it('should calculate elapsed time up to the current time if completedAt is not provided', () => {
    const createdAt = new Date('2025-03-01T00:00:00Z')
    mockDateNow.mockReturnValue(new Date('2025-03-01T01:03:07Z').getTime())

    const elapsedTime = calculateElapsedTime(createdAt, undefined)

    expect(elapsedTime).toBe('1h 3m') // Only the largest non-zero interval
  })

  it('should dynamically include the second largest interval when it becomes non-zero', () => {
    const createdAt = new Date('2025-03-01T00:00:00Z')
    const completedAt = new Date('2025-03-01T02:01:28Z')

    const elapsedTime = calculateElapsedTime(createdAt, completedAt)

    expect(elapsedTime).toBe('2h 1m') // Includes the second largest interval when non-zero
  })
})
