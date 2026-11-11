# frozen_string_literal: true

# A ActiveJob::Retry exponential backoff strategy that checks the rate limit
# headers on GitHub TooManyRequests error and adds an extra delay for that time,
# or 2 minutes if not found to all Octokit::TooManyRequests, and increases the
# range of random delay that's added to these retries, to help spread out
# these retries a bit more.
class RateLimitBackoffStrategy < ActiveJob::Retry::ExponentialBackoffStrategy
  # From octokit.rb: https://github.com/octokit/octokit.rb/blob/
  # dbea2c6c72637965f75517c006cea0870c920798/lib/octokit/error.rb#L325
  RATE_LIMITED_ERRORS = [
    Octokit::TooManyRequests,
    Octokit::AbuseDetected,
  ].freeze
  MAX_JITTER_SECONDS = 30 * 60

  def retry_delay(attempt, exception)
    return super unless RATE_LIMITED_ERRORS.any? { |e| exception.is_a?(e) }

    # Time at which the current rate limit window resets in UTC epoch seconds.
    expires_at = exception.response_headers["X-RateLimit-Reset"].to_i
    remaining = Time.at(expires_at).in_time_zone - Time.now.in_time_zone
    remaining = remaining.positive? ? remaining : 120

    # Pad the remaining time with exponential back-off
    # Implementation from super-class:
    # https://github.com/isaacseymour/activejob-retry/blob/64aee6912b2931a4c7b3823e70090f71711bb71d/lib/
    # active_job/retry/exponential_backoff_strategy.rb
    (attempt**4 + 15 + (rand(MAX_JITTER_SECONDS) * (attempt + 1))).seconds + remaining.seconds
  end
end
