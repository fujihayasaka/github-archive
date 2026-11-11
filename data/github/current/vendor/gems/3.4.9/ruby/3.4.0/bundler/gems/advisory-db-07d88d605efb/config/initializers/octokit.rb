# frozen_string_literal: true

require "github_throttle"

Octokit.middleware = Faraday::RackBuilder.new do |builder|
  builder.request :retry, exceptions: [Octokit::ServerError]

  builder.use Octokit::Middleware::FollowRedirects
  builder.use Octokit::Response::RaiseError
  builder.use Octokit::Response::FeedParser
  builder.use GitHubThrottle::Middleware

  builder.adapter Faraday.default_adapter
end

Octokit.configure do |c|
  c.api_endpoint = ENV.fetch("GITHUB_API_ENDPOINT", "https://api.github.com/")
end
