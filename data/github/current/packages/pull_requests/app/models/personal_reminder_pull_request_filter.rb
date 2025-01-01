# typed: false
# frozen_string_literal: true
# Given a personal reminder, return relevant pull requests.
#
# Filtering is done in two steps:
# 1. Scope filtering: pull requests are excluded by building up an ActiveRecord scope. This happens before fetching pull requests from the database.
# 2. Array filtering: pull requests are filtered out of an array. This happens after fetching pull requests from the database.
class PersonalReminderPullRequestFilter < ReminderPullRequestFilterBase
  def self.run(reminder)
    new(reminder).run
  end

  def run
    return run_in_batches if GitHub.flipper[:scheduled_reminders_process_job_with_batches].enabled?(reminder.user || reminder)

    open_pull_requests_scope = base_scope(repo_ids: reminder.accessible_repository_ids)

    pull_request_ids = []
    if reminder.include_review_requests
      pull_request_ids += open_pull_requests_scope.joins(:review_requests).merge(waiting_on_user_scope).pluck(:id)
    end

    if reminder.include_team_review_requests
      pull_request_ids += open_pull_requests_scope.joins(:review_requests).merge(waiting_on_teams_scope).pluck(:id)
    end

    pull_requests = PullRequest.where(id: pull_request_ids).to_a
    ReminderResultSet.new(pull_requests, [])
  end

  def run_in_batches
    pull_requests = []

    base_scope_in_batches(repo_ids: reminder.accessible_repository_ids) do |open_pull_requests_scope|
      pull_request_ids = []
      if reminder.include_review_requests
        pull_request_ids += open_pull_requests_scope.joins(:review_requests).merge(waiting_on_user_scope).pluck(:id)
      end

      if reminder.include_team_review_requests
        pull_request_ids += open_pull_requests_scope.joins(:review_requests).merge(waiting_on_teams_scope).pluck(:id)
      end

      pull_requests += PullRequest.where(id: pull_request_ids).to_a
    end

    ReminderResultSet.new(pull_requests, [])
  end

  attr_reader :reminder
  def initialize(reminder)
    @reminder = reminder
  end

  def waiting_on_user_scope
    ReviewRequest.type_users.pending.where(reviewer_id: reminder.user_id)
  end

  def waiting_on_teams_scope
    ReviewRequest.type_teams.pending.where(reviewer_id: reminder.user.team_ids)
  end
end
