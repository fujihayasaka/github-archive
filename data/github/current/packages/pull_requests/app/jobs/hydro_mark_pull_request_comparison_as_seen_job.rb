# typed: true
# frozen_string_literal: true

class HydroMarkPullRequestComparisonAsSeenJob < HydroMessageJob
  queue_as :hydro_mark_pr_comparison_as_seen
  retry_on_dirty_exit

  def initialize(protobuf:, headers:, schema:, timestamp:, timestamp_nano:, message:, queue:)
    super

    @user_id = message[:user_id]
    @pull_request_id = message[:pull_request_id]
    @start_oid = message[:start_oid]
    @end_oid = message[:end_oid]
  end

  def perform
    user = User.find(@user_id)
    pull_request = PullRequest.find(@pull_request_id)

    start_commit, end_commit = pull_request.compare_repository.commits.find([@start_oid, @end_oid])

    comparison = PullRequest::Comparison.new(pull: pull_request, start_commit:, end_commit:, base_commit: start_commit, viewer: user, base_repository: pull_request.base_repository, head_repository: pull_request.head_repository)
    comparison.mark_as_seen(user: user)
  end
end
