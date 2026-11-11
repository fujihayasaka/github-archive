# typed: true
# frozen_string_literal: true

module PullRequests::ComparisonTracking
  # Track that a user has viewed a pull request comparison by publishing a Hydro event.
  sig { params(comparison: PullRequest::Comparison, user: User).void }
  def async_mark_comparison_as_seen(comparison, user:)
    message = {
      pull_request_id: comparison.pull.id,
      user_id: user.id,
      start_oid: comparison.start_commit.oid,
      end_oid: comparison.end_commit.oid,
    }

    GitHub.hydro_publisher.publish(
      message,
      schema: "github.pull_requests.v1.MarkPullRequestComparisonAsSeen",
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
    )
  end
end
