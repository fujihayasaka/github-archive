export class MergeError extends Error {
  declare readonly ruleErrors: string[]
  constructor(message: string, ruleErrors: string[] = [], cause?: unknown) {
    super(message)
    this.name = 'MergeError'
    this.ruleErrors = ruleErrors
    this.cause = cause
  }
}
