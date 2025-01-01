import type {Cancellable} from '../../hooks/common/timeouts/use-timeout'

/**
 * Tracks the progress of a single, active bulk update request.
 *
 * This class helps us manage persistent toast notifications that show to display the progress
 * of a bulk update. It's purpose is to ensure that we consistently communicate the progress of
 * only the most recently started bulk update request (previous requests are discarded), and that
 * we display a smooth progress indicator (in spite of potentially receiving update events out-of-order).
 *
 * This class is not exported; consumers should use the `BulkUpdateProgressSingleton` instance instead.
 */
class BulkUpdateProgress {
  public requestId?: string
  public percentage: number
  public outstandingTimeouts: Array<Cancellable>

  constructor() {
    this.requestId = undefined
    this.percentage = 0
    this.outstandingTimeouts = []
  }

  public pending = (requestId: string | undefined): boolean => {
    if (!requestId) return false

    this.reset()
    this.requestId = requestId

    return true
  }

  public progress = (requestId: string | undefined, percentage: number): number | undefined => {
    if (this.requestId !== requestId) return

    // Ensure that the percentage always increases: any call that would decrease the percentage is ignored.
    // This helps us deal with events that arrive out-of-order.
    //
    // For additional safety, also clamp the percentage to the range [0, 100].
    this.percentage = Math.min(Math.max(0, this.percentage, percentage), 100)
    return this.percentage
  }

  public complete = (requestId: string | undefined, delay: number, clearPersistedToast: () => Cancellable) => {
    if (this.requestId !== requestId) return false

    this.percentage = 100

    const resetStateTimeoutId = setTimeout(() => {
      this.requestId = undefined
      this.percentage = 0
    }, delay)

    this.outstandingTimeouts.push({cancel: () => clearTimeout(resetStateTimeoutId)})
    this.outstandingTimeouts.push(clearPersistedToast())

    return true
  }

  public reset = () => {
    for (const cancellable of this.outstandingTimeouts) {
      cancellable.cancel()
    }

    this.outstandingTimeouts.splice(0, Infinity)
    this.requestId = undefined
    this.percentage = 0
  }
}

export const BulkUpdateProgressSingleton = new BulkUpdateProgress()
