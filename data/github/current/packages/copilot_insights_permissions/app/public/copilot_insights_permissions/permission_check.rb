# typed: strict
# frozen_string_literal: true

module CopilotInsightsPermissions
  class PermissionCheck
    sig { params(business: T.nilable(Business), user: T.nilable(User)).void }
    def initialize(business: nil, user: nil)
      @business = business
      @user = user
    end

    sig { returns(T::Boolean) }
    def copilot_insights_usage_feature_available?
      feature_available?(:copilot_insights_usage)
    end

    sig { returns(T::Boolean) }
    def copilot_insights_code_generation_feature_available?
      feature_available?(:copilot_usage_lines_of_code)
    end

    sig { returns(T::Boolean) }
    def copilot_insights_usage_metrics_api_available?
      return false unless dotcom_env?
      return false unless feature_flag_enabled?(:copilot_insights_usage)

      true
    end

    private

    sig { params(feature: Symbol).returns(T::Boolean) }
    def feature_available?(feature)
      dotcom_env? &&
        valid_enterprise_type? &&
        feature_flag_enabled?(feature) &&
        has_copilot_insights_access?
    end

    sig { returns(T::Boolean) }
    def has_copilot_insights_access?
      is_enterprise_admin? || is_billing_manager?
    end

    sig { params(feature: Symbol).returns(T::Boolean) }
    def feature_flag_enabled?(feature)
      @business&.feature_flag_enabled?(feature, default: false) ||
        @user&.feature_flag_enabled?(feature, default: false) ||
        false
    end

    sig { returns(T::Boolean) }
    def dotcom_env?
      !GitHub.enterprise? && !GitHub.multi_tenant_enterprise?
    end

    sig { returns(T::Boolean) }
    def valid_enterprise_type?
      !!@business
    end

    sig { returns(T::Boolean) }
    def is_enterprise_admin?
      return false unless @business && @user

      @business.owner?(@user)
    end

    sig { returns(T::Boolean) }
    def is_billing_manager?
      return false unless @business && @user

      @business.billing_manager?(@user)
    end
  end
end
