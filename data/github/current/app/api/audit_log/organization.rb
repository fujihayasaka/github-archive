# typed: true
# frozen_string_literal: true

class Api::AuditLog::Organization < Api::App
  include Api::AuditLog::Helpers

  # organization audit-log
  get "/organizations/:organization_id/audit-log", operation_id: "orgs/get-audit-log" do
    ActiveRecord::Base.connected_to(role: :reading) do
      @target = find_org!

      deliver_error! 404 unless org_api_enabled?

      @enterprise = @target.business

      control_access :read_org_audit_log_via_api,
        resource: @target,
        forbid: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true

      if params[:include] == "all"
        build_and_execute_all_query
      elsif params[:include] == "git"
        build_and_execute_git_query
      else
        build_and_execute_query
      end
    rescue Driftwood::TwirpUtil::InvalidArgumentError
      deliver_error!(400, message: "The supplied query is invalid")
    rescue Driftwood::TwirpUtil::RateLimitedError
      deliver_error!(429, message: "You can't perform that action at this time. Please try again later.")
    end
  end

  private

  def rate_limit_configuration
    return unless GitHub.flipper[:audit_log_api_rate_limit].enabled?(current_user)
    return if GitHub.flipper[:audit_log_rate_limit_exempt].enabled?(current_user)
    Api::RateLimitConfiguration.for(
      Api::RateLimitConfiguration::AUDIT_LOG_FAMILY,
      self,
    )
  end

  def identifier_params
    { org_id: @target.id }
  end

  def find_org
    return @current_org if defined?(@current_org)
    @current_org = super || find_org_by_login
  end

  # Private: Selects the Organization defined in the URL request.
  def find_org_by_login
    login = params[:organization_id].to_s
    # Note - Org.find_by_login reads from replica
    login.present? && Organization.find_by_login(login)
  end

  def org_api_enabled?
    @target.business_plus? || GitHub.single_business_environment?
  end
end
