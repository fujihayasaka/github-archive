# typed: true
# frozen_string_literal: true

class Api::AuditLog::Enterprise < Api::Enterprise::App
  include Api::AuditLog::Helpers

  # business audit-log
  get "/enterprises/:enterprise_id/audit-log", operation_id: "enterprise-admin/get-audit-log" do
    ActiveRecord::Base.connected_to(role: :reading) do
      @target = find_enterprise!

      control_access :standard_authorization,
        resource: @target,
        permission: :read_enterprise_audit_logs,
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
    Api::RateLimitConfiguration.for(
      Api::RateLimitConfiguration::AUDIT_LOG_FAMILY,
      self,
    )
  end

  def identifier_params
    GitHub.single_business_environment? ? {} : { business_id: @target.id }
  end
end
