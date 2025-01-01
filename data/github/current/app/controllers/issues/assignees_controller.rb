# typed: true
# frozen_string_literal: true

class Issues::AssigneesController < IssuesController

  include Issues::RateLimitsDependency

  before_action :login_required
  before_action :issue_required
  before_action :require_xhr, only: :unassign_self

  skip_before_action :issue_modifiers_only, only: [:update, :unassign_self]
  skip_before_action :writable_repository_required, only: [:update, :unassign_self]

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
    unless current_issue.assignable_by?(actor: current_user)
      raise ArgumentError.new "#{current_user&.display_login} does not have permission to manage assignees in this repository."
    end

    # This is the most simple way to determine that this is not a PR
    # and that the current repository has issues disabled.
    if current_issue.pull_request_id.nil? && !current_repository.has_issues?
      raise ArgumentError.new "Issues are disabled for this repository."
    end

    if current_repository.locked_on_migration?
      raise ArgumentError.new "This repository is currently locked for migration."
    end

    if current_repository.archived?
      raise ArgumentError.new "This repository is archived."
    end

    # Extract the assigned ID's
    user_assignee_ids = params.dig(:issue, :user_assignee_ids)
    if user_assignee_ids.nil?
      raise ArgumentError.new("User assignees parameter is malformed")
    end

    saved = T.let(false, T::Boolean)
    assignee_data = {}
    update_issue_orchestration = T.let(nil, T.untyped)
    assigned_ids = params[:issue][:user_assignee_ids].reject(&:empty?).map(&:to_i)
    assignee_data[:user_assignee_ids] = assigned_ids

    IssueOrchestration.transaction do
      current_issue.skip_update_issue_orchestration = true
      saved = current_issue.save
      if saved
        update_issue_orchestration = IssueOrchestration.update_issue!(actor: current_user, issue: current_issue)
        update_issue_orchestration.data[:assignee_data] = assignee_data
      end
    end

    if !saved
      raise ArgumentError.new "Could not save issue"
    end

    current_issue.notify_tracked_by_issue

    begin
      update_issue_orchestration.execute! if update_issue_orchestration
    rescue ActiveRecord::RecordInvalid, Orchestration::RetryStepError => e
      raise if e.is_a?(Orchestration::RetryStepError) && !current_repository&.feature_enabled?(:retry_assignees_errors)
      # address possible race condition where two processes update
      # assignees at the same time
      if e.message =~ /has already been taken/
        raise ArgumentError.new "Could not save issue"
      end
    end

    track_issue_edits_from_project_board(edited_fields: ["assignees"])

    if request&.xhr?
      respond_to do |format|
        format.html do
          render partial: "issues/sidebar/show/assignees", locals: { issue: current_issue, inline: params[:inline] }
        end
      end
    else
      redirect_to :back
    end
  rescue ArgumentError => e
    if request&.xhr?
      render json: { errors: e.message }, status: :unprocessable_entity
    else
      flash[:error] = e.message
      redirect_to :back
    end
  end

  def unassign_self # rubocop:todo GitHub/UseRestfulActions
    Issue.transaction do
      current_issue.remove_assignees(current_user)
      if current_issue.save!
        respond_to do |format|
          format.html do
            render partial: "issues/sidebar/show/assignees", locals: { issue: current_issue }
          end
        end
      end
    end
  rescue ActiveRecord::RecordInvalid
    render json: { errors: current_issue.errors }, status: :unprocessable_entity
  end
end
