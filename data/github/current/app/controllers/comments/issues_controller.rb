# typed: true
# frozen_string_literal: true

class Comments::IssuesController < ApplicationController
  include Issues::RateLimitsDependency

  before_action :require_can_open_issue, only: :create

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
    issue_attributes = Issues::CreateIssueAttributes.new(
      title: issue_params[:title],
      body: issue_params[:body],
      repository: repository,
    )

    result = Issues.domain.create(issue_attributes, current_user)

    case result
    when GH::Result::Ok
      respond_to do |format|
        format.html do
          redirect_to issue_path(owner, repository, result.value)
        end
      end
    else
      render_404 and return
    end
  end

  private

  def issue_params
    params.require(:issue).permit(:title, :body, :repository_id)
  end

  memoize def repository
    Repositories::Public.find_active!(issue_params[:repository_id])
  end

  memoize def owner
    repository.owner
  end

  def target_for_conditional_access
    owner
  end

  def require_can_open_issue
    has_access = Api::AccessControl.access_allowed? \
      resource: repository,
      user: current_user,
      repo: repository,
      verb: :open_issue,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    render_404 and return unless has_access
    render_404 and return if !repository.has_issues?
  end
end
