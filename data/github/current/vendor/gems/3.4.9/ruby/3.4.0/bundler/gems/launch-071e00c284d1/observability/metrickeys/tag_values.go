package metrickeys

// NonHTTPError is used by http_result where no HTTP response was returned
const NonHTTPError = "non_http_error"

// InvalidHTTPStatus for status codes outside the range allowed by the HTTP spec
const InvalidHTTPStatus = "invalid_status"

// ActionsService refers to the Actions Service, formerly called AZP
const ActionsService = "azp"

// GitHubAPI is our non-GQL API
const GitHubAPI = "github_api"

// AtQueueTime - occurs when we queue a build
const AtQueueTime = "queue_time"

// AtActionsParseTime - point at which we parse files (in contrast to when AZP does post-Queue)
const AtActionsParseTime = "actions_parse_time"

// GitHubGQL relates to our GraphQL API
const GitHubGQL = "github_gql"
