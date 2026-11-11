# frozen_string_literal: true

# # github/rest_client contains dependabot-api's octokit client extensions
require "github/rest_client"

require "metrics_faraday_middleware"
require "dependabot/octokit_middleware/raise_sync_error"
require "dependabot/octokit_middleware/raise_gone_error"

# GitHub client metrics via Faraday middleware
Octokit.middleware = Octokit::Default::MIDDLEWARE.dup.tap do |stack|
  stack.response :logger if Rails.env.development?
  # We want to intercept specific responses that should trigger a SynchronizeRepoState in the calling code before
  # the Octokit error handling is applied.
  stack.insert_after(Octokit::Response::RaiseError, Dependabot::OctokitMiddleware::RaiseSyncError)

  # The version of Octokit we use doesn't include a custom 410 client error type but these errors do get
  # returned from GitHub REST API.
  stack.insert_after(Octokit::Response::RaiseError, Dependabot::OctokitMiddleware::RaiseGoneError)

  # We only want to inject the metrics middleware in production
  if Rails.env.production?
    stack.insert_after(Octokit::Response::RaiseError, MetricsFaradayMiddleware, client: MetricsClient)
  end
end
