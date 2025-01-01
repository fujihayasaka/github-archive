import {describe, it, expect, vi} from '@github-ui/tests'
import {postTask} from '../scheduler'

describe('scheduler', () => {
  it('can schedule a callback', async () => {
    vi.useFakeTimers()
    const callback = vi.fn()
    postTask(callback)
    expect(callback).toHaveBeenCalledTimes(0)
    await vi.runAllTimersAsync()
    expect(callback).toHaveBeenCalledTimes(1)
  })

  it('aborts a scheduled callback when the signal is aborted', async () => {
    vi.useFakeTimers()
    const callback = vi.fn()
    const controller = new AbortController()
    postTask(callback, {signal: controller.signal})
    expect(callback).toHaveBeenCalledTimes(0)
    controller.abort()
    await vi.runAllTimersAsync()
    expect(callback).toHaveBeenCalledTimes(0)
  })
})
