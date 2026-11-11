# typed: true
# frozen_string_literal: true

class FilterProvidersController < ApplicationController
  layout false

  before_action :ensure_query_value_present, only: [:show]
  around_action :track_request_time, only: [:index, :show]

  LOGGED_OUT_SUGGESTION_LIMIT = 25
  FILTER_SUGGESTION_LIMIT = 500

  private

  def ensure_query_value_present
    head :bad_request unless query_value.present?
  end

  # Override to return structured JSON for SSO-required XHR responses instead of
  # a bare 401, so the frontend can distinguish "SSO required" from "invalid
  # filter value" and display an actionable error message.
  def require_active_external_identity_session
    # For non-XHR requests: guard the case where the target is unknown before
    # delegating to the parent, because the parent's render_external_identity_session_required
    # raises ArgumentError for :no_target_for_conditional_access.
    unless request.xhr?
      target = safe_target_for_conditional_access
      return true if target == :no_target_for_conditional_access
      return super
    end

    # For XHR without the structured errors flag, delegate to the parent which
    # returns a bare head :unauthorized.
    return super unless FeatureFlag.vexi.enabled?(:issues_dashboard_sso_structured_errors, current_user, default: false)

    # For XHR with the structured errors flag on: we cannot call super because
    # it renders head :unauthorized before we can substitute structured JSON.
    # Replicate the parent's early-exit guards verbatim so behaviour is identical
    # for all non-SSO-enforcement paths (development EMU bootstrap, enforcement
    # disabled, signed-token auth, fresh session).
    if GitHub::AppEnvironment.development?
      if user_session && user_session.user
        user_session.user.reload unless user_session.user.respond_to?(:is_enterprise_managed?)
        if user_session.user.is_enterprise_managed?
          return false if FeatureFlag.vexi.enabled?(:emu_dev_bootstrap, user_session.user.enterprise_managed_business, default: false)
        end
      end
    end

    return unless GitHub.external_identity_session_enforcement_enabled?
    return true if signed_token_authed?
    return true if external_identity_session_fresh?

    target = safe_target_for_conditional_access
    return true if target == :no_target_for_conditional_access

    sso_target = target.respond_to?(:external_identity_session_owner) ? target.external_identity_session_owner : nil

    if sso_target.is_a?(Organization)
      render json: {
        error: "sso_required",
        type: "saml",
        organization: sso_target.display_login,
        sso_url: org_idm_saml_initiate_url(sso_target, return_to: request.referrer),
      }, status: :unauthorized
    elsif sso_target.is_a?(Business)
      sso_url = if sso_target.oidc_enabled?
        idm_oidc_initiate_enterprise_url(sso_target)
      else
        idm_saml_initiate_enterprise_url(sso_target)
      end

      render json: {
        error: "sso_required",
        type: sso_target.oidc_enabled? ? "oidc" : "saml",
        enterprise: sso_target.slug,
        sso_url: sso_url,
      }, status: :unauthorized
    else
      head :unauthorized
    end
  end

  def respond_payload(json)
    respond_to do |format|
      format.json do
        render json: json
      end
    end
  end

  def respond_error(status_code, message)
    respond_to do |format|
      format.json do
        render json: { error: message }, status: status_code
      end
    end
  end

  # Used for database `LIKE` queries
  memoize def like_query_value
    return "%" unless query_value.present?
    sanitize_sql_like(query_value)
  end

  def sanitize_sql_like(value)
    "%#{ActiveRecord::Base.sanitize_sql_like(value&.to_s&.strip || "")}%"
  end

  def query_value
    params[:q].to_s
  end

  def has_search_query?
    query_value.present?
  end

  def track_request_time
    tags = [
      "controller:#{controller_name}",
      "action:#{action_name}",
    ]

    track_time(metric: "filter_providers.dist.time", tags: tags) do
      yield
    end
  end

  def maximum_result_limit
    logged_in? ? FILTER_SUGGESTION_LIMIT : LOGGED_OUT_SUGGESTION_LIMIT
  end
end
