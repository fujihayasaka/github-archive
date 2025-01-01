/**
 * Tracks the N most recent update requests for which we invalidated the query cache eagerly on success of the
 * request, (as opposed to lazily on receipt of a live update socket message).
 *
 * Note that this class only exported for testing purposes: in production code, we should only use the singleton
 * instance exported further below.
 */
export class EagerQueryInvalidation {
  private requestIds: Array<string>
  private index = 0

  constructor(size: number = 10) {
    this.requestIds = new Array(size)
  }

  public register = (requestId: string) => {
    this.requestIds[this.index] = requestId
    this.index = (this.index + 1) % this.requestIds.length
  }

  public has = (requestId: string) => {
    return this.requestIds.includes(requestId)
  }
}

export const EagerQueryInvalidationSingleton = new EagerQueryInvalidation()
