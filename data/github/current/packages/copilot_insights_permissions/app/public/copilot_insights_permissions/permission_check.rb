# typed: strict
# frozen_string_literal: true

module CopilotInsightsPermissions
  class PermissionCheck
    sig { params(business: T.nilable(Business), organization: T.nilable(Organization), user: T.nilable(User)).void }
    def initialize(business: nil, organization: nil, user: nil)
      @business = business
      @organization = organization
      @user = user
      @copilot_business = T.let(nil, T.nilable(Copilot::Business))
      @copilot_organization = T.let(nil, T.nilable(Copilot::Organization))
    end

    sig { returns(T::Boolean) }
    def copilot_insights_usage_feature_available?
      return false if FeatureFlag.vexi.enabled?(:copilot_metrics_blocklist, @business, default: false)
      return false unless base_usage_gates_pass?

      feature_flag_enabled?(:copilot_insights_usage) || copilot_insights_policy_enabled?
    end

    sig { returns(T::Boolean) }
    def copilot_insights_usage_feature_opted_in?
      return false unless copilot_insights_usage_feature_available?
      return true if feature_flag_enabled?(:copilot_insights_usage)
      return false unless copilot_insights_policy_enabled?

      opted_in?
    end

    sig { returns(T::Boolean) }
    def copilot_insights_code_generation_feature_available?
      return false if FeatureFlag.vexi.enabled?(:copilot_metrics_blocklist, @business, default: false)
      feature_available?(:copilot_usage_lines_of_code)
    end

    sig { returns(T::Boolean) }
    def copilot_insights_usage_metrics_api_available?
      return false unless copilot_insights_supported_env?
      return false if FeatureFlag.vexi.enabled?(:copilot_metrics_blocklist, @business, default: false)
      return false unless valid_enterprise_type?
      return false unless feature_flag_enabled?(:copilot_insights_usage) || (copilot_insights_policy_enabled? && opted_in?)
      true
    end

    sig { returns(T::Boolean) }
    def copilot_insights_usage_metrics_org_api_available?
      return false unless copilot_insights_supported_env?
      return false if @organization&.business && FeatureFlag.vexi.enabled?(:copilot_metrics_blocklist, @organization.business, default: false)
      return false if FeatureFlag.vexi.enabled?(:copilot_metrics_blocklist, @organization, default: false)
      return false unless organization_opted_in_for_insights_policies?
      true
    end

    sig { returns(T::Boolean) }
    def opted_in?
      Copilot::Policies::Insights.enabled?(copilot_business)
    end

    sig { returns(T::Boolean) }
    def organization_opted_in_for_insights_policies?
      Copilot::Policies::Insights.enabled?(copilot_organization)
    end

    private

    sig { params(feature: Symbol).returns(T::Boolean) }
    def feature_available?(feature)
      copilot_insights_supported_env? &&
        valid_enterprise_type? &&
        feature_flag_enabled?(feature) &&
        has_copilot_insights_access?
    end

    sig { returns(T::Boolean) }
    def base_usage_gates_pass?
      copilot_insights_supported_env? && valid_enterprise_type? && has_copilot_insights_access?
    end

    sig { returns(T::Boolean) }
    def has_copilot_insights_access?
      is_enterprise_admin? || is_billing_manager? || can_read_enterprise_copilot_metrics?
    end

    sig { params(feature: Symbol).returns(T::Boolean) }
    def feature_flag_enabled?(feature)
      @business&.feature_flag_enabled?(feature, default: false) ||
        @user&.feature_flag_enabled?(feature, default: false) ||
        false
    end

    sig { returns(T::Boolean) }
    def copilot_insights_policy_enabled?
      if copilot_business.is_standalone_business?
        feature_flag_enabled?(:copilot_insights_public_preview)
      else
        feature_flag_enabled?(:enterprise_ai_controls) && feature_flag_enabled?(:copilot_insights_public_preview)
      end
    end

    sig { returns(Copilot::Business) }
    def copilot_business
      @copilot_business ||= Copilot::Business.new(T.must(@business))
    end

    sig { returns(Copilot::Organization) }
    def copilot_organization
      @copilot_organization ||= Copilot::Organization.new(T.must(@organization))
    end

    sig { returns(T::Boolean) }
    def copilot_insights_supported_env?
      # Return true for dotcom (not enterprise and not multi-tenant)
      return true if !GitHub.enterprise? && !GitHub.multi_tenant_enterprise?

      # Return true for multi-tenant if feature flag is enabled
      return true if GitHub.multi_tenant_enterprise? && feature_flag_enabled?(:copilot_insights_multi_tenant_enterprise)

      false
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

    sig { returns(T::Boolean) }
    def can_read_enterprise_copilot_metrics?
      return false unless @business && @user

      Authz.domain.check_allowed(@user, :read_enterprise_copilot_metrics, @business)
    end
  end
end
