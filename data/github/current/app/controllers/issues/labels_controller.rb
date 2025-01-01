# typed: true
# frozen_string_literal: true

class Issues::LabelsController < IssuesController
  include Issues::RateLimitsDependency
  include Issues::RepositoryClusterDependency

  around_action :with_replica_repository_cluster, only: [:update]
  before_action :issue_required
  before_action :require_can_label, only: [:update]
  before_action :require_not_locked, only: [:update]
  before_action :require_not_archived, only: [:update]
  before_action :require_repository_has_issues, only: [:update]

  skip_before_action :issue_modifiers_only, only: [:update]
  skip_before_action :writable_repository_required, only: [:update]
  skip_before_action :content_authorization_required, only: [:update]

  RATE_LIMITS_FEATURES = [
    :issues_service_mutative_actions_rate_limits, # are rate limits for issues-owned controller/actions enabled
    :issues_service_mutative_actions_rate_limits_new_max, # what are the new max rate limits for issues-owned controller/actions
    :issues_rate_limit_circuit_breaker, # whether to enable the circuit breaker for spammy users creating issues via issues#create
  ]

  preload_features RATE_LIMITS_FEATURES

  rate_limit_requests \
    max: :issues_service_rate_limits_max,
    ttl: 1.hour,
    key: :default_rate_limit_key,
    at_limit: :issues_service_rate_limits_at_limit,
    if: :issues_service_rate_limits_enabled?

  def update
    label_attrs = []
    label_ids = params[:issue][:labels]

    if label_ids.any?
      labels = if GitHub.flipper[:issue_dependency_removal].enabled?
        Issues.domain.labels.by_repository_and_normalized_ids(repository_id: T.must(current_repository.id), label_ids:)
      else
        current_repository.load_labels(label_ids)
      end
      current_issue.replace_labels(labels) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
      current_issue.notify_tracked_by_issue
    end

    head :unprocessable_entity and return unless current_issue.valid?

    respond_to do |format|
      format.html do
        render partial: "issues/sidebar/show/labels", locals: { issue: current_issue.reload, inline: params[:inline] } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end
  end

  private

  def privacy_check
    with_replica_repository_cluster { super }
  end

  def require_can_label
    head :forbidden and return unless current_issue.labelable_by?(actor: current_user)
  end

  def require_repository_has_issues
    head :unprocessable_entity and return if current_issue.pull_request_id.nil? && !current_repository.has_issues?
  end

  def require_not_locked
    head :unprocessable_entity and return if current_repository.locked_on_migration?
  end

  def require_not_archived
    head :unprocessable_entity and return if current_repository.archived?
  end
end
