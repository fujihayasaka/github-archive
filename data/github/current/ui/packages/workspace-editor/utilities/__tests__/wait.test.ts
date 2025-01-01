import {randomInt} from '../random-int'
import {wait} from '../wait'

// time tollerance in milliseconds, bump up if tests are flaky
// due to race condition issues
const TIME_TOLLERANCE_MS = 10

describe('wait', () => {
  beforeEach(() => {
    jest.useFakeTimers()
  })

  afterEach(() => {
    jest.useRealTimers()
  })

  it('should wait for specified number of milliseconds', async () => {
    const delayMs = randomInt(50, 5)
    const startTime = performance.now()

    jest.runAllTimersAsync()

    await wait(delayMs)

    const elapsedTime = performance.now() - startTime
    const timeDelta = elapsedTime - delayMs

    // elapsedTime can only be equal or slightly larger than the actual delay value
    expect(timeDelta).toBeGreaterThanOrEqual(0)
    expect(timeDelta).toBeLessThanOrEqual(TIME_TOLLERANCE_MS)
  })
})
