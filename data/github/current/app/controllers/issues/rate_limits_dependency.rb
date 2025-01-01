# typed: true
# frozen_string_literal: true

module Issues
  module RateLimitsDependency
    extend T::Helpers
    requires_ancestor { ApplicationController }

    ISSUES_INDEX_WITHOUT_REFERER_RATE_LIMIT_MAX = 30
    ISSUES_DASHBOARD_WITHOUT_REFERER_RATE_LIMIT_MAX = 10
    ISSUES_BOT_RATE_LIMIT_MAX = 10

    ISSUES_SERVICE_RATE_LIMIT_NEW = 400
    ISSUES_SERVICE_RATE_LIMIT = 1000
    ISSUES_SERVICE_RATE_LIMIT_ERROR = "You've attempted this action too many times. Please try again later."

    def issues_service_rate_limits_enabled?
      mutative_request_method? && user_or_global_feature_enabled?(:issues_service_mutative_actions_rate_limits)
    end

    def issue_service_use_new_rate_limit?
      return false if user_or_global_feature_enabled?(:opt_out_of_issues_service_mutative_actions_rate_limits_new_max)

      user_or_global_feature_enabled?(:issues_service_mutative_actions_rate_limits_new_max)
    end

    def issues_service_rate_limits_max
      if mutative_request_method? && issue_service_use_new_rate_limit?
        ISSUES_SERVICE_RATE_LIMIT_NEW
      else
        ISSUES_SERVICE_RATE_LIMIT
      end
    end

    def issues_service_rate_limits_at_limit
      if request.referrer
        flash[:error] = ISSUES_SERVICE_RATE_LIMIT_ERROR
        redirect_to :back
      end
    end

    def issues_create_rate_limit_log_key
      return "issue_create_limiter_log.#{current_user.id}" if issues_create_rate_limit_enabled?

      "#{controller_name.parameterize}-#{action_name.parameterize}-count"
    end

    def issues_create_rate_limit_max
      return 0 if issues_create_rate_limit_enabled?

      issues_service_rate_limits_max
    end

    def issues_create_rate_limit_enabled?
      logged_in? && current_user.spammy? && repository_feature_enabled?(:issues_rate_limit_circuit_breaker)
    end

    def issues_create_rate_limit_key
      return "issue_create_limiter.#{current_user.id}" if issues_create_rate_limit_enabled?

      default_rate_limit_key
    end

    def issues_create_rate_limit_at_limit
      if issues_create_rate_limit_enabled?
        GitHub.dogstats.increment("rate_limited", tags: [
          "controller:#{controller_name}",
          "spammy:#{current_user.spammy?}",
          "circuit_breaker:#{repository_feature_enabled?(:issues_rate_limit_circuit_breaker)}"
        ])
      else
        issues_service_rate_limits_at_limit
      end
    end

    def issues_create_or_service_rate_limits_enabled?
      issues_create_rate_limit_enabled? || issues_service_rate_limits_enabled?
    end

    def issues_index_rate_limit_key
      session_id = request.env.key?("rack.session") && request.env["rack.session"]["session_id"]
      return "#{controller_name.underscore}:#{action_name}:#{session_id}" if session_id

      default_rate_limit_key
    end

    def issues_index_without_referer_limits_enabled?
      !request.referrer.present? && GitHub.flipper[:issues_index_without_referer_limits].enabled?
    end

    def issues_index_rate_limiting_enabled?
      issues_bot_rate_limiting_enabled? || issues_index_without_referer_limits_enabled?
    end

    def issues_index_rate_limit_at_limit
      message = "You've attempted this action too many times. Please try again later."

      respond_to do |format|
        format.any do
          render \
            body: message,
            formats: :html,
            status: 429
        end
      end
    end

    def issues_index_rate_limit_max
      if issues_bot_rate_limiting_enabled?
        ISSUES_BOT_RATE_LIMIT_MAX
      elsif issues_index_without_referer_limits_enabled?
        ISSUES_INDEX_WITHOUT_REFERER_RATE_LIMIT_MAX
      else
        GitHub::RateLimitedRequest::DEFAULT_RATE_LIMIT_MAX
      end
    end

    def issues_dashboard_rate_limit_key
      session_id = request.env.key?("rack.session") && request.env["rack.session"]["session_id"]
      return "#{controller_name.underscore}:#{action_name}:#{session_id}" if session_id

      default_rate_limit_key
    end

    def issues_dashboard_without_referer_limits_enabled?
      !request.referrer.present? && GitHub.flipper[:issues_dashboard_without_referer_limits].enabled?
    end

    def issues_dashboard_rate_limit_at_limit
      message = "You've attempted this action too many times. Please try again later."

      respond_to do |format|
        format.any do
          render \
            body: message,
            formats: :html,
            status: 429
        end
      end
    end

    def issues_bot_rate_limiting_enabled?
      request_category == "robot"
    end

    def issues_bot_rate_limit_key
      session_id = request.env.key?("rack.session") && request.env["rack.session"]["session_id"]
      return "#{controller_name.underscore}:#{action_name}:#{session_id}" if session_id

      default_rate_limit_key
    end

    def issues_bot_rate_limit_at_limit
      message = "You've attempted this action too many times. Please try again later."

      respond_to do |format|
        format.any do
          render \
            body: message,
            formats: :html,
            status: 429
        end
      end
    end
  end
end
