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

export class CompletionTokensLimitReachedResponseError extends ModelClientError {
  constructor() {
    super(
      'The completion tokens limit has been reached for this response. Please increase the max completion tokens parameter or try a different prompt.',
    )
    this.name = 'CompletionTokensLimitReachedResponseError'
    this.canRetry = true
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
export const PlaygroundChatSuggestion = 'github_models.playground.chat_suggestion'
export const GettingStartedButtonClicked = 'github_models.getting_started.clicked'
export const RunCodespaceButtonClicked = 'github_models.run_codespace.clicked'
export const ImproveSystemPromptClicked = 'github_models.improve_system_prompt.clicked'
export const GenerateSystemPromptClicked = 'github_models.generate_system_prompt.clicked'
export const UseImprovedSystemPromptClicked = 'github_models.use_improved_system_prompt.clicked'
export const CancelImprovedSystemPromptClicked = 'github_models.cancel_improved_system_prompt.clicked'
export const ImproveUserPromptClicked = 'github_models.improve_user_prompt.clicked'
export const GenerateUserPromptClicked = 'github_models.generate_user_prompt.clicked'
export const UseImprovedUserPromptClicked = 'github_models.use_improved_user_prompt.clicked'
export const CancelImprovedUserPromptClicked = 'github_models.cancel_improved_user_prompt.clicked'

// Codespaces
export const templateRepositoryNwo = 'github/codespaces-models'

// OpenAI o- series models
export const o1ModelNames = ['o1-mini', 'o1-preview', 'o1', 'o3-mini', 'o3']

// Currently, only GPT-4o, grok-3, and grok-3-mini support JSON Schema Structured Output
export const modelsWithJsonSchemaSupport = ['gpt-4o', 'grok-3', 'grok-3-mini']
