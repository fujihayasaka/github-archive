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
      next run_in_batches if FeatureFlag.vexi.enabled?(:scheduled_reminders_process_job_with_batches, reminder.user || reminder, default: false)

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
    if updated_limits_enabled?
      base_scope_in_batches_experiment(repo_ids: reminder.accessible_repository_ids)
    else
      base_scope_in_batches_original(repo_ids: reminder.accessible_repository_ids)
    end
  end

  def base_scope_in_batches_original(repo_ids: reminder.accessible_repository_ids)
    pull_requests = []
    pull_requests_waiting_on_author = []

    base_scope_in_batches(repo_ids: reminder.accessible_repository_ids) do |scope|
      if reminder.ignored_labels_values.any? || reminder.required_labels_values.any?
        scope = scope.preload(issue: :labels)
      end
      scope = filter_by_age(scope)
      scope = filter_by_stale(scope)
      scope = ignore_drafts(scope)

      scope.in_batches do |unfiltered_pull_requests| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        prs_waiting_on_review, prs_waiting_on_author = filter_pull_requests(unfiltered_pull_requests.to_a) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

        pull_requests += prs_waiting_on_review
        pull_requests_waiting_on_author += prs_waiting_on_author
      end
    end

    ReminderResultSet.new(pull_requests, pull_requests_waiting_on_author)
  end

  def base_scope_in_batches_experiment(repo_ids: reminder.accessible_repository_ids)
    pull_requests = []
    pull_requests_waiting_on_author = []

    base_scope_in_batches_without_join(repo_ids: repo_ids) do |scope|
      prs_waiting_on_review, prs_waiting_on_author = build_filtered_scope_without_join_experiment(scope)
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
    scope = filter_ignored_terms_with_database(scope)
    ## filter labels
    scope = filter_labels_with_database(scope) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    ## filter approved
    scope = ignore_approved_with_database(scope)
    ## filter by remind author - pull requests on author
    pull_requests_on_author = filter_by_remind_author_with_database(scope)
    ## filter by team requested for review
    pull_requests_need_review = filter_by_team_is_requested_for_review(scope).to_a # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    pull_requests_need_review = require_pending_review_request(pull_requests_need_review)

    pull_requests_need_review -= pull_requests_on_author
    [pull_requests_need_review, pull_requests_on_author]
  end

  def build_filtered_scope_without_join_experiment(scope)
    scope = filter_by_age(scope)
    scope = filter_by_stale(scope)
    scope = ignore_drafts(scope)
    ## filter ignored terms if any
    scope = filter_ignored_terms_with_database_without_join_experiment(scope)
    ## filter labels
    scope = filter_labels_with_database_without_join_experiment(scope) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    ## filter approved
    scope = ignore_approved_with_database(scope)
    ## filter by remind author - pull requests on author
    pull_requests_on_author = filter_by_remind_author_with_database(scope)
    ## filter by team requested for review
    pull_requests_need_review = filter_by_team_is_requested_for_review(scope).to_a # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    pull_requests_need_review = require_pending_review_request(pull_requests_need_review)

    pull_requests_need_review -= pull_requests_on_author
    [pull_requests_need_review, pull_requests_on_author]
  end

  def filter_ignored_terms_with_database(scope)
    return scope unless reminder.ignored_terms_values.any?

    ignored_terms = reminder.ignored_terms_values.map { |_term| "issues.title NOT LIKE ?" }.join(" AND ")
    scope.where(ignored_terms, *reminder.ignored_terms_values.map { |term| "%#{term}%" })
  end

  def filter_ignored_terms_with_database_without_join_experiment(scope)
    return scope unless reminder.ignored_terms_values.any?

    ignored_terms = reminder.ignored_terms_values.map { |_term| "issues.title NOT LIKE ?" }.join(" AND ")
    scope
    .joins("INNER JOIN `issues` ON `issues`.`pull_request_id` = `pull_requests`.`id`")
    .where(ignored_terms, *reminder.ignored_terms_values.map { |term| "%#{term}%" })
  end

  def filter_labels_with_database(scope)
    if reminder.ignored_labels_values.any?
      ignored_issue_ids = scope
      .joins("INNER JOIN `issues_labels` ON `issues_labels`.`issue_id` = `issues`.`id`")
      .joins("INNER JOIN `labels` ON `labels`.`id` = `issues_labels`.`label_id`")
      .where("labels.lowercase_name IN (?)", reminder.ignored_labels_values.map(&:downcase))
      .distinct
      .pluck(:id)

      scope = scope.where("pull_requests.id NOT IN (?)", ignored_issue_ids) unless ignored_issue_ids.empty?
    end
    if reminder.required_labels_values.any?
      required_issue_ids = scope
      .joins("INNER JOIN `issues_labels` ON `issues_labels`.`issue_id` = `issues`.`id`")
      .joins("INNER JOIN `labels` ON `labels`.`id` = `issues_labels`.`label_id`")
      .where("labels.lowercase_name IN (?)", reminder.required_labels_values.map(&:downcase))
      .distinct
      .pluck(:id)

      if required_issue_ids.empty?
        scope = scope.none # if no required labels are found, return an empty scope
      else
        scope = scope.where("pull_requests.id IN (?)", required_issue_ids)
      end
    end
    scope
  end

  def filter_labels_with_database_without_join_experiment(scope)
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

  def ignore_approved_with_database(scope)
    return scope if reminder.include_approved?
    max_approvals = reminder.ignore_after_approval_count

    filtered_pull_request_ids = ReviewRequest.
      joins(:pull_request_reviews).
      where(pull_request_id: scope.pluck(:id)). # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      where(pull_request_reviews: { state: PullRequestReview.state_value(:approved) }).
      group(:pull_request_id).
      having("COUNT(*) >= ?", max_approvals).
      pluck(:pull_request_id)

    scope.where("pull_requests.id NOT IN (?)", filtered_pull_request_ids)
  end

  def filter_by_remind_author_with_database(scope)
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
