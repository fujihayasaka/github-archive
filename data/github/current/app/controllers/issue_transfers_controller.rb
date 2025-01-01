# typed: true
# frozen_string_literal: true

class IssueTransfersController < AbstractRepositoryController
  include ControllerMethods::Issues
  include Issues::RateLimitsDependency

  before_action :login_required
  before_action :load_current_issue
  before_action :require_can_create, only: [:create]

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

  def create
    target_repo = Repository.find_by(id: params[:repository_id])
    unless target_repo.present?
      render_404 and return
    end

    transfer = IssueTransfer.new(
      old_issue: @issue,
      old_repository: @issue.repository,
      new_repository: target_repo,
      actor: current_user,
    )

    transfer.valid?
    validation_errors = transfer.errors

    redirect_to :back and return if validation_errors.any? { |e| [:actor, :old_issue, :old_repository, :new_repository].include? e.attribute }

    unless transfer.async_transfer!(create_labels_if_missing: create_labels_if_missing?)
      redirect_to :back and return
    end

    flash[:notice] = "Issue transfer in progress"
    redirect_to issue_path transfer.new_issue
  end

  private

  def create_labels_if_missing?
    params[:create_labels_if_missing].present? && params[:create_labels_if_missing] == "true"
  end

  def load_current_issue
    @issue ||= current_repository.issues.find_by_number params[:id]
    redirect_to :back and return unless @issue
  end

  def require_can_create
    render_404 unless @issue.can_transfer_issue? current_user, current_repository
  end
end
