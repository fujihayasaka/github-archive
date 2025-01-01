# typed: true
# frozen_string_literal: true

class Api::AuditLog::Enterprise < Api::Enterprise::App
  include Api::AuditLog::Helpers

  # business audit-log
  get "/enterprises/:enterprise_id/audit-log", operation_id: "enterprise-admin/get-audit-log" do
    ActiveRecord::Base.connected_to(role: :reading) do
      @target = find_enterprise!

      # because neither result in the experiment is necessary for controlling access,
      # we will use a dark-shipped FF to control experiment participation
      # and leave the experiment at 100%, so we only add this to execution time when necessary
      if FeatureFlag.vexi.enabled?(:run_biz_audit_log_fgp_api_experiment, default: false)
        _ = Authz.domain # ensure domain is initialized to avoid counting init in experiment perf
        Scientist.run "biz_audit_log_fgp_api_experiment" do |e|
          e.use do
            # access_allowed is what control_access calls
            access_allowed?(:read_business_and_org_audit_log,
              resource: @target,
              forbid: true,
              allow_integrations: true,
              allow_user_via_granular_actor: true,
              enforce_oauth_app_policy: true)
          end
          e.try do
            # access_allowed is what control_access calls
            access_allowed?(:standard_authorization,
              resource: @target,
              permission: :read_enterprise_audit_logs,
              forbid: true,
              allow_integrations: true,
              allow_user_via_granular_actor: true,
              enforce_oauth_app_policy: true)
          end
        end
      end

      if @target&.feature_flag_enabled?(:use_biz_audit_log_fgp_api, default: false)
        control_access :standard_authorization,
          resource: @target,
          permission: :read_enterprise_audit_logs,
          forbid: true,
          allow_integrations: true,
          allow_user_via_granular_actor: true,
          enforce_oauth_app_policy: true
      else
        control_access :read_business_and_org_audit_log,
          resource: @target,
          forbid: true,
          allow_integrations: true,
          allow_user_via_granular_actor: true,
          enforce_oauth_app_policy: true
      end

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
    return unless FeatureFlag.vexi.enabled?(:audit_log_api_rate_limit, current_user, default: false)
    return if FeatureFlag.vexi.enabled?(:audit_log_rate_limit_exempt, current_user, default: false)
    Api::RateLimitConfiguration.for(
      Api::RateLimitConfiguration::AUDIT_LOG_FAMILY,
      self,
    )
  end

  def identifier_params
    GitHub.single_business_environment? ? {} : { business_id: @target.id }
  end
end
