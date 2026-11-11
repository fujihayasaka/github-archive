# typed: true
# frozen_string_literal: true

module Settings
  class NavigationView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include GitHub::Memoizer

    def orgs_with_admin_or_manager_access
      @orgs ||= begin
        orgs_with_access_hash = Hash.new { |h, k| h[k] = nil }
        current_user.owned_organizations.each { |org| orgs_with_access_hash[org] = :admin }
        current_user.billing_manager_organizations.each { |org| orgs_with_access_hash[org] ||= :billing_manager }
        orgs_with_access_hash.reject { |o| o.deleted }.sort_by { |o| o[0].display_login }.to_h
      end
    end

    def enterprises_with_admin_or_manager_access
      @enterprises ||= begin
        hash = {}
        current_user.businesses(membership_type: :admin).each { |e| hash[e] = :admin }
        current_user.businesses(membership_type: :billing_manager).each { |e| hash[e] ||= :billing_manager }
        hash.sort_by { |e| e[0].slug }.to_h
      end
    end

    def org_settings_path_params(organization, org_permission)
      path = case org_permission
      when :admin
        :settings_org_profile_path
      when :billing_manager
        :settings_org_billing_path
      end
      [path, organization]
    end

    def enterprise_settings_path_params(enterprise, permission)
      path = case permission
      when :admin
        :settings_profile_enterprise_path
      when :billing_manager
        :settings_billing_enterprise_path
      end
      [path, enterprise]
    end

    def billing_manager?(permission)
      permission == :billing_manager
    end

    def should_verify_email?
      logged_in? && current_user.should_verify_email?
    end

    def show_organizations_button?
      return false if current_user&.is_enterprise_managed? && current_user&.enterprise_managed_business&.seats_plan_basic?
      true
    end

    def show_enterprise_button?
      return false if GitHub.single_business_environment?
      true
    end

    def show_teams_button?
      current_user.teams.any?
    end

    def show_premium_request_page_link?
      return false if ::Copilot::User.new(current_user).use_token_based_billing?
      copilot_user = ::Copilot::Public::User.for(current_user)
      copilot_user.has_ci_access?
    end

    def show_ai_usage_page_link?
      public_user = ::Copilot::Public::User.for(current_user)
      return false unless public_user.has_ci_access?

      copilot_user = ::Copilot::User.new(current_user)
      copilot_user.use_token_based_billing?
    end

    # Check feature flag before instantiating Copilot::User to avoid unnecessary object creation
    def show_copilot_memory_page_link?
      return false unless logged_in?
      return false unless FeatureFlag.vexi.enabled?(:copilot_memory_enablement_policy, current_user, default: false)

      copilot_user = ::Copilot::User.new(current_user)
      return false unless ::Copilot::Policies::Memory.user_scoped_memory_available_for?(copilot_user)

      ::Copilot::Policies::Memory.effective_value(copilot_user) == "enabled"
    end

    memoize def user_has_sso_orgs?
      return false unless logged_in? && current_user

      user_org_ids = current_user.organization_ids
      return false if user_org_ids.empty?

      # Check if user has any org with direct SAML provider
      return true if ::Organization::SamlProvider.batched_scope(:organization_id, values: user_org_ids).any?

      # Check if user has any org whose business has SAML or OIDC provider
      user_business_ids = ::Business::OrganizationMembership
        .batched_scope(:organization_id, values: user_org_ids)
        .pluck(:business_id)
        .uniq

      return false if user_business_ids.empty?

      ::Business::SamlProvider.batched_scope(:business_id, values: user_business_ids).any? ||
        ::Business::OIDCProvider.batched_scope(:business_id, values: user_business_ids).any?
    end
  end
end
