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
      FeatureFlag.vexi.enabled?(:global_nav_react_teams_settings_page, current_user, default: false) && current_user.teams.any?
    end

    memoize def user_has_sso_orgs?
      logged_in? && current_user.organizations.any?(&:saml_sso_present?)
    end
  end
end
