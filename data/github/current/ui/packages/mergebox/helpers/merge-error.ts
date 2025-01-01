export class MergeError extends Error {
  constructor(
    message: string,
    public readonly ruleErrors: string[] = [],
  ) {
    super(message)
    this.name = 'MergeError'
  }
}
