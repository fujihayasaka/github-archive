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
      run_in_batches
    end
  end

  def run_in_batches
    pull_requests = []
    pull_requests_waiting_on_author = []

    base_scope_in_batches(repo_ids: reminder.accessible_repository_ids) do |scope|
      prs_waiting_on_review, prs_waiting_on_author = build_filtered_scope(scope)
      pull_requests += prs_waiting_on_review
      pull_requests_waiting_on_author += prs_waiting_on_author
    end

    pull_requests = apply_limits(pull_requests)
    pull_requests_waiting_on_author = apply_limits(pull_requests_waiting_on_author)

    ReminderResultSet.new(pull_requests, pull_requests_waiting_on_author)
  end

  def build_filtered_scope(scope)
    scope = filter_by_age(scope)
    scope = filter_by_stale(scope)
    scope = ignore_drafts(scope)
    ## filter ignored terms if any
    scope = filter_ignored_terms(scope)
    ## filter labels
    scope = filter_labels(scope) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    ## filter approved
    scope = ignore_approved(scope)
    ## filter by remind author - pull requests on author
    pull_requests_on_author = filter_by_remind_author(scope)
    ## filter by team requested for review
    pull_requests_need_review = filter_by_team_is_requested_for_review(scope).to_a # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    pull_requests_need_review = require_pending_review_request(pull_requests_need_review)

    pull_requests_need_review -= pull_requests_on_author
    [pull_requests_need_review, pull_requests_on_author]
  end

  def filter_ignored_terms(scope)
    return scope unless reminder.ignored_terms_values.any?

    ignored_terms = reminder.ignored_terms_values.map { |_term| "issues.title NOT LIKE ?" }.join(" AND ")
    scope
    .joins("INNER JOIN `issues` ON `issues`.`pull_request_id` = `pull_requests`.`id`")
    .where(ignored_terms, *reminder.ignored_terms_values.map { |term| "%#{term}%" })
  end

  def filter_labels(scope)
    if reminder.ignored_labels_values.any?
      # Use NOT EXISTS subquery to exclude PRs with ignored labels
      scope = scope.where(
        "NOT EXISTS (
          SELECT 1 FROM issues
          INNER JOIN issues_labels ON issues_labels.issue_id = issues.id
          INNER JOIN labels ON labels.id = issues_labels.label_id
          WHERE issues.pull_request_id = pull_requests.id
          AND labels.lowercase_name IN (?)
        )",
        reminder.ignored_labels_values.map(&:downcase)
      )
    end

    if reminder.required_labels_values.any?
      # Use EXISTS subquery to include only PRs with required labels
      scope = scope.where(
        "EXISTS (
          SELECT 1 FROM issues
          INNER JOIN issues_labels ON issues_labels.issue_id = issues.id
          INNER JOIN labels ON labels.id = issues_labels.label_id
          WHERE issues.pull_request_id = pull_requests.id
          AND labels.lowercase_name IN (?)
        )",
        reminder.required_labels_values.map(&:downcase)
      )
    end
    scope
  end

  def ignore_approved(scope)
    return scope if reminder.include_approved?
    max_approvals = reminder.ignore_after_approval_count

    if FeatureFlag.vexi.enabled?(:scheduled_reminders_fix_approval_count, reminder.user, default: false)
      # Find PRs that have >= max_approvals (these should be excluded)
      # Query PullRequestReview directly to count all approvals, not just those from review requests
      pull_request_ids_to_exclude = PullRequestReview.
        where(pull_request_id: scope.pluck(:id)). # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        where(state: PullRequestReview.state_value(:approved)).
        group(:pull_request_id).
        having("COUNT(*) >= ?", max_approvals).
        pluck(:pull_request_id)

      return scope if pull_request_ids_to_exclude.empty?

      scope.where.not(id: pull_request_ids_to_exclude)
    else
      filtered_pull_request_ids = ReviewRequest.
        joins(:pull_request_reviews).
        where(pull_request_id: scope.pluck(:id)). # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        where(pull_request_reviews: { state: PullRequestReview.state_value(:approved) }).
        group(:pull_request_id).
        having("COUNT(*) >= ?", max_approvals).
        pluck(:pull_request_id)

      scope.where("pull_requests.id NOT IN (?)", filtered_pull_request_ids)
    end
  end

  def filter_by_remind_author(scope)
    return [] unless reminder.include_reviewed_prs
    if reminder_team_filter.filtered_by_team?
      scope = scope.where("pull_requests.user_id IN (?)", reminder_team_filter.member_ids)
    end

    any_review_requests = ReviewRequest.
    where(pull_request_id: scope.pluck(:id)). # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    not_dismissed.
    distinct.
    pluck(:pull_request_id)

    pull_request_ids_with_pending_review_requests = ReviewRequest.
      where(pull_request_id: scope.pluck(:id)). # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      not_dismissed.
      pending.
      distinct.
      pluck(:pull_request_id)

    non_pending_review_request_ids = any_review_requests.difference(pull_request_ids_with_pending_review_requests)

    ## filter by num required reviews
    if reminder.needed_reviews > 0
      fulfilled_reviews_by_pr = PullRequest.latest_fulfilled_reviews_count_for(pull_request_ids: scope.pluck(:id)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      fulfilled_review_ids = fulfilled_reviews_by_pr.select { |_, count| count.to_i >= reminder.needed_reviews }.keys
      fulfilled_review_ids_with_review_requests = any_review_requests.intersection(fulfilled_review_ids)
      scope = scope.where("pull_requests.id IN (?)",  fulfilled_review_ids_with_review_requests + non_pending_review_request_ids)
    else
      scope = scope.where("pull_requests.id IN (?)", non_pending_review_request_ids)
    end
    scope.to_a # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  attr_reader :reminder
  def initialize(reminder)
    @reminder = reminder
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

  # filter by team review requests if we require_review_request
  def filter_by_team_is_requested_for_review(pull_requests)
    return pull_requests unless reminder.require_review_request

    reminder_team_filter.run(pull_requests)
  end

  def reminder_team_filter
    reminder_team_filter ||= ReminderTeamFilter.new(reminder)
  end

end
