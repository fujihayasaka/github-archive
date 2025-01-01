export class ApiError extends Error {
  declare readonly response: Response
  constructor(message: string, response: Response) {
    super(message)
    this.response = response
    this.name = 'ApiError'
  }
}
