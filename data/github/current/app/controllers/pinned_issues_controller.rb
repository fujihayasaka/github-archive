# typed: true
# frozen_string_literal: true

class PinnedIssuesController < AbstractRepositoryController
  include Issues::RateLimitsDependency

  before_action :login_required
  before_action :write_access_required

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
    if issue(params[:id]).pin(actor: current_user)
      flash[:notice] = "The issue has been pinned."
    else
      flash[:error] = "The issue could not be pinned."
    end
    redirect_to :back
  end

  def destroy
    if issue(params[:id]).unpin(actor: current_user)
      flash[:notice] = "The issue has been unpinned."
    else
      flash[:error] = "The issue could not be unpinned."
    end
    redirect_to :back
  end

  def prioritize # rubocop:todo GitHub/UseRestfulActions
    issue_ids = params[:issue_ids] || []
    if issue_ids.present?
      current_repository.reorder_pinned_issues(issue_ids.map(&:to_i))
    end
    head :ok
  end

  private

  def issue(number)
    @issue ||= current_repository.issues.find_by!(number: number)
  end

  def write_access_required
    render_404 unless current_repository.can_pin_issues?(current_user)
  end
end
