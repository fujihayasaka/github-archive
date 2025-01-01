export class ModelClientError extends Error {
  canRetry: boolean = false
  tokenLimitReached: boolean = false

  constructor(...args: ConstructorParameters<typeof Error>) {
    super(...args)
    this.name = 'ModelClientError'
  }
}

export class TimeoutError extends ModelClientError {
  constructor(...args: ConstructorParameters<typeof Error>) {
    super(...args)
    this.name = 'TimeoutError'
  }
}
export const TokenLimitReachedResponseErrorDescription = 'The conversation token limit has been reached. '
export class TokenLimitReachedResponseError extends ModelClientError {
  constructor() {
    super(TokenLimitReachedResponseErrorDescription)
    this.name = 'TokenLimitReachedResponseError'
    this.tokenLimitReached = true
  }
}
export class TooManyRequestsError extends ModelClientError {
  constructor(retryAfter: string | null) {
    const message = retryAfter
      ? `Rate limited, please try again in ${retryAfter} seconds.`
      : 'Rate limited, please try again later.'
    super(message)
    this.canRetry = true
    this.name = 'TooManyRequestsError'
  }
}

// Analytics events
export const PlaygroundChatRequestSent = 'github_models.playground.chat_request.sent'
export const PlaygroundChatRateLimited = 'github_models.playground.chat_request.rate_limited'
export const PlaygroundChatRequestStreamingStarted = 'github_models.playground.chat_request.streaming_started'
export const PlaygroundChatRequestStreamingCompleted = 'github_models.playground.chat_request.streaming_completed'
export const GettingStartedButtonClicked = 'github_models.getting_started.clicked'
export const RunCodespaceButtonClicked = 'github_models.run_codespace.clicked'

// Codespaces
export const templateRepositoryNwo = 'github/codespaces-models'
