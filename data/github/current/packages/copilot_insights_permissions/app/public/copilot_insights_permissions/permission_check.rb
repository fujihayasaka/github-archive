# typed: strict
# frozen_string_literal: true

module CopilotInsightsPermissions
  class PermissionCheck

    include GitHub::Memoizer

    sig { params(business: T.nilable(Business), organization: T.nilable(Organization), user: T.nilable(User)).void }
    def initialize(business: nil, organization: nil, user: nil)
      @business = T.let(business || organization&.business, T.nilable(Business))
      @organization = organization
      @user = user
    end

    sig { returns(T::Boolean) }
    memoize def copilot_insights_usage_feature_available?
      return false if FeatureFlag.vexi.enabled?(:copilot_metrics_blocklist, @business, default: false)
      return false unless base_usage_gates_pass?
      true
    end

    sig { returns(T::Boolean) }
    memoize def copilot_insights_usage_feature_opted_in?
      return false unless copilot_insights_usage_feature_available?
      opted_in?
    end

    sig { returns(T::Boolean) }
    memoize def copilot_insights_code_generation_feature_available?
      return false if FeatureFlag.vexi.enabled?(:copilot_metrics_blocklist, @business, default: false)
      feature_available?(:copilot_usage_lines_of_code)
    end

    sig { returns(T::Boolean) }
    memoize def copilot_insights_usage_metrics_api_available?
      return false unless copilot_insights_supported_env?
      return false if FeatureFlag.vexi.enabled?(:copilot_metrics_blocklist, @business, default: false)
      return false unless valid_enterprise_type?
      return false unless opted_in?
      true
    end

    sig { returns(T::Boolean) }
    memoize def copilot_insights_usage_metrics_org_api_available?
      return false unless copilot_insights_supported_env?
      return false if feature_flag_enabled?(:copilot_metrics_blocklist)
      return false unless organization_opted_in_for_insights_policies?
      true
    end

    sig { returns(T::Boolean) }
    memoize def copilot_insights_org_dashboard_feature_available?
      return false unless @organization
      return false unless copilot_insights_supported_env?
      return false if feature_flag_enabled?(:copilot_metrics_blocklist)
      true
    end

    sig { returns(T::Boolean) }
    memoize def can_view_org_copilot_insights?
      return false unless @organization && @user
      return true if @organization.adminable_by?(@user)
      Authz.domain.check_allowed(@user, :read_organization_copilot_metrics, @organization)
    end

    sig { returns(T::Boolean) }
    memoize def copilot_insights_org_dashboard_accessible?
      copilot_insights_org_dashboard_feature_available? && can_view_org_copilot_insights?
    end

    sig { returns(T::Boolean) }
    memoize def opted_in?
      business = copilot_business
      return false unless business
      Copilot::Policies::Insights.enabled?(business)
    end

    sig { returns(T::Boolean) }
    memoize def organization_opted_in_for_insights_policies?
      org = copilot_organization
      return false unless org
      org.insights_enabled?
    end

    sig { returns(T::Boolean) }
    memoize def copilot_insights_supported_env?
      # Return true for dotcom (not enterprise and not multi-tenant)
      return true if !GitHub.enterprise? && !GitHub.multi_tenant_enterprise?

      # Return true for multi-tenant if feature flag is enabled
      return true if GitHub.multi_tenant_enterprise? && feature_flag_enabled?(:copilot_insights_multi_tenant_enterprise)

      false
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
    memoize def base_usage_gates_pass?
      copilot_insights_supported_env? && valid_enterprise_type? && has_copilot_insights_access?
    end

    sig { returns(T::Boolean) }
    def has_copilot_insights_access?
      is_enterprise_admin? || is_billing_manager? || can_read_enterprise_copilot_metrics?
    end

    sig { params(feature: Symbol).returns(T::Boolean) }
    def feature_flag_enabled?(feature)
      @business&.feature_flag_enabled?(feature, default: false) ||
        @organization&.feature_flag_enabled?(feature, default: false) ||
        @user&.feature_flag_enabled?(feature, default: false) ||
        false
    end

    sig { returns(T.nilable(Copilot::Business)) }
    memoize def copilot_business
      Copilot::Business.new(@business) if @business
    end

    sig { returns(T.nilable(Copilot::Organization)) }
    memoize def copilot_organization
      Copilot::Organization.new(@organization) if @organization
    end

    sig { returns(T::Boolean) }
    memoize def valid_enterprise_type?
      !!@business
    end

    sig { returns(T::Boolean) }
    memoize def is_enterprise_admin?
      return false unless @business && @user

      @business.owner?(@user)
    end

    sig { returns(T::Boolean) }
    memoize def is_billing_manager?
      return false unless @business && @user

      @business.billing_manager?(@user)
    end

    sig { returns(T::Boolean) }
    memoize def can_read_enterprise_copilot_metrics?
      return false unless @business && @user

      Authz.domain.check_allowed(@user, :read_enterprise_copilot_metrics, @business)
    end
  end
end
