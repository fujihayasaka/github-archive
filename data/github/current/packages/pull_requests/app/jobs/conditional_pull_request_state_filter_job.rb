# typed: true
# frozen_string_literal: true

class ConditionalPullRequestStateFilterJob < ApplicationJob
  use_replicas ApplicationRecord::IssuesPullRequests

  retry_on_dirty_exit

  queue_as :conditional_pull_request_state_filter

  include Scientist

  def perform(ids:, states:)
    return if GitHub.enterprise?

    scope = PullRequest.where(id: ids)

    science "pull_request.conditional_state_filter" do |experiment|
      experiment.use { pull_request_state_filter_results(scope, states).pluck(:id).sort }
      experiment.try { conditional_pull_request_state_filter_results(scope, states).pluck(:id).sort }
    end
  end

  # This method is copied from the filter method in app/platform/helpers/pull_request_state_filter.rb
  def pull_request_state_filter_results(scope, states)
    join_performance_patch = "`issues`.`repository_id` = `pull_requests`.`repository_id`"

    case states.sort
    when %w[closed]
      scope.where(merged_at: nil).joins(:issue).where(issues: { state: "closed" }).where(join_performance_patch)
    when %w[closed merged]
      scope.joins(:issue).where("merged_at IS NOT NULL OR issues.state = ?", "closed").where(join_performance_patch)
    when %w[closed open]
      scope.where(merged_at: nil)
    when %w[merged]
      scope.where("merged_at IS NOT NULL")
    when %w[merged open]
      scope.joins(:issue).where("pull_requests.merged_at IS NOT NULL OR issues.state = ?", "open").where(join_performance_patch)
    when %w[open]
      scope.joins(:issue).where(issues: { state: "open" }).where(join_performance_patch)
    else
      scope
    end
  end

  def conditional_pull_request_state_filter_results(scope, states)
    case states.sort
    when %w[closed]
      scope.where(merged_at: nil, status: "closed")
    when %w[closed merged]
      scope.where("merged_at IS NOT NULL OR status = ?", "closed")
    when %w[closed open]
      scope.where(merged_at: nil)
    when %w[merged]
      scope.where("merged_at IS NOT NULL")
    when %w[merged open]
      scope.where("merged_at IS NOT NULL OR status = ?", "open")
    when %w[open]
      scope.where(status: "open")
    else
      scope
    end
  end

end
