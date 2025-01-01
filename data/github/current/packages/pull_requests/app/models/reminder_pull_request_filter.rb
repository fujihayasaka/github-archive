# typed: false
# frozen_string_literal: true

# Given a reminder, returns relevant pull requests.
#
# Filtering is done in two steps:
# 1. Scope filtering: pull requests are excluded by building up an ActiveRecord scope. This happens before fetching pull requests from the database.
# 2. Array filtering: pull requests are filtered out of an array. This happens after fetching pull requests from the database.
class ReminderPullRequestFilter < ReminderPullRequestFilterBase
  def self.run(reminder)
    new(reminder).run
  end

  def run
    GitHub.dogstats.distribution_time("reminders.dist.pull_request_filter.run") do
      next run_in_batches if GitHub.flipper[:scheduled_reminders_process_job_with_batches].enabled?(reminder.user || reminder)

      scope = base_scope(repo_ids: reminder.accessible_repository_ids)

      if reminder.ignored_labels_values.any? || reminder.required_labels_values.any?
        scope = scope.preload(issue: :labels)
      end

      scope = ignore_drafts(scope)
      scope = filter_by_age(scope)
      scope = filter_by_stale(scope)

      pull_requests = []
      pull_requests_waiting_on_author = []
      scope.in_batches do |unfiltered_pull_requests|
        prs_waiting_on_review, prs_waiting_on_author = filter_pull_requests(unfiltered_pull_requests.to_a)

        pull_requests += prs_waiting_on_review
        pull_requests_waiting_on_author += prs_waiting_on_author
      end

      ReminderResultSet.new(pull_requests, pull_requests_waiting_on_author)
    end
  end

  def run_in_batches
    pull_requests = []
    pull_requests_waiting_on_author = []

    base_scope_in_batches(repo_ids: reminder.accessible_repository_ids) do |scope|
      if reminder.ignored_labels_values.any? || reminder.required_labels_values.any?
        scope = scope.preload(issue: :labels)
      end

      scope = ignore_drafts(scope)
      scope = filter_by_age(scope)
      scope = filter_by_stale(scope)

      scope.in_batches do |unfiltered_pull_requests|
        prs_waiting_on_review, prs_waiting_on_author = filter_pull_requests(unfiltered_pull_requests.to_a)

        pull_requests += prs_waiting_on_review
        pull_requests_waiting_on_author += prs_waiting_on_author
      end
    end

    ReminderResultSet.new(pull_requests, pull_requests_waiting_on_author)
  end

  def filter_pull_requests(pull_requests)
    pull_requests = ignore_approved(pull_requests)
    pull_requests = filter_ignored_terms(pull_requests) if reminder.ignored_terms_values.any?
    if reminder.ignored_labels_values.any? || reminder.required_labels_values.any?
      pull_requests = filter_labels(pull_requests)
    end

    pull_requests_on_author = filter_by_remind_author(pull_requests)

    pull_requests_need_review = filter_by_team_is_requested_for_review(pull_requests)
    pull_requests_need_review = require_pending_review_request(pull_requests_need_review)
    pull_requests_need_review -= pull_requests_on_author

    [pull_requests_need_review, pull_requests_on_author]
  end

  attr_reader :reminder
  def initialize(reminder)
    @reminder = reminder
  end

  def filter_by_remind_author(pull_requests)
    return [] unless reminder.include_reviewed_prs

    target_author_pull_requests = pull_requests

    if reminder_team_filter.filtered_by_team?
      target_author_pull_requests = pull_requests.select do |pull_request|
        reminder_team_filter.member_ids.include?(pull_request.user_id)
      end
    end

    target_author_pull_requests = require_any_review_request(target_author_pull_requests)
    filter_to_num_required_review_rules(target_author_pull_requests)
  end

  def filter_by_age(scope)
    min_age = reminder.min_age

    return scope if min_age.zero?

    scope.where("pull_requests.created_at < ?", min_age.hours.ago)
  end

  def filter_by_stale(scope)
    min_staleness = reminder.min_staleness

    return scope if min_staleness.zero?

    scope.where("pull_requests.updated_at < ?", min_staleness.hours.ago)
  end

  def ignore_drafts(scope)
    return scope if reminder.include_drafts?

    scope.where(draft: false)
  end

  def require_pending_review_request(pull_requests)
    return pull_requests unless reminder.require_review_request

    pull_request_ids_with_pending_review = ReviewRequest.
      where(pull_request_id: pull_requests.map(&:id)).
      pending.
      not_dismissed.
      distinct.
      pluck(:pull_request_id)

    pull_requests.select do |pull_request|
      pull_request_ids_with_pending_review.include?(pull_request.id)
    end
  end

  def require_any_review_request(pull_requests)
    pull_request_ids_with_any_review = ReviewRequest.
      where(pull_request_id: pull_requests.map(&:id)).
      not_dismissed.
      distinct.
      pluck(:pull_request_id)

    pull_requests.select do |pull_request|
      pull_request_ids_with_any_review.include?(pull_request.id)
    end
  end

  def filter_to_num_required_review_rules(pull_requests)
    pull_request_ids_with_pending_review_requests = ReviewRequest.
      where(pull_request_id: pull_requests.map(&:id)).
      not_dismissed.
      pending.
      distinct.
      pluck(:pull_request_id)

    if pull_requests.any? && reminder.needed_reviews > 0
      fulfilled_reviews_by_pr = PullRequest.latest_fulfilled_reviews_count_for(pull_request_ids: pull_requests.map(&:id))
    end

    pull_requests.reject do |pull_request|
      if reminder.needed_reviews > 0
        next false if fulfilled_reviews_by_pr[pull_request.id].to_i >= reminder.needed_reviews
      end

      pull_request_ids_with_pending_review_requests.include?(pull_request.id)
    end
  end

  def ignore_approved(pull_requests)
    return pull_requests if reminder.include_approved?

    max_approvals = reminder.ignore_after_approval_count
    pull_request_ids_with_too_many_approvals = ReviewRequest.
      where(pull_request_id: pull_requests.map(&:id)).
      joins(:pull_request_reviews).
      where(pull_request_reviews: { state: PullRequestReview.state_value(:approved) }).
      group(:pull_request_id).
      having("COUNT(*) >= ?", max_approvals).
      pluck(:pull_request_id)

    pull_requests.reject do |pull_request|
      pull_request_ids_with_too_many_approvals.include?(pull_request.id)
    end
  end

  # filter by team review requests if we require_review_request
  def filter_by_team_is_requested_for_review(pull_requests)
    return pull_requests unless reminder.require_review_request

    reminder_team_filter.run(pull_requests)
  end

  def filter_ignored_terms(pull_requests)
    reminder_ignored_terms_values = reminder.ignored_terms_values

    pull_requests.reject do |pull_request|
      reminder_ignored_terms_values.any? { |term| pull_request.title.include?(term) }
    end
  end

  def filter_labels(pull_requests)
    if reminder.ignored_labels_values.any?
      reminder_ignored_labels_values = reminder.ignored_labels_values.map(&:downcase)

      pull_requests = pull_requests.reject do |pull_request|
        labels = pull_request.issue.labels.map(&:name).map(&:downcase)
        (reminder_ignored_labels_values & labels).any?
      end
    end

    if reminder.required_labels_values.any?
      reminder_required_labels_values = reminder.required_labels_values.map(&:downcase)

      pull_requests = pull_requests.select do |pull_request|
        labels = pull_request.issue.labels.map(&:name).map(&:downcase)
        (reminder_required_labels_values & labels).any?
      end
    end

    pull_requests
  end

  def reminder_team_filter
    reminder_team_filter ||= ReminderTeamFilter.new(reminder)
  end
end
