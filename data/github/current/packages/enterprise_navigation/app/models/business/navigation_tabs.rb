# typed: true
# frozen_string_literal: true

class Business
  class NavigationTabs
    include GitHub::Memoizer
    include UrlHelpers
    include EnterpriseNavigation::Links::All
    include EnterpriseNavigation::Links::SharedDependency
    include GitHub::ResilienceMixin
    include ComplianceReportHelper

    def self.for(business:, **opts)
      new(business, **opts).tabs
    end

    sig { returns T.nilable(Business) }
    attr_reader :business

    sig { returns T.nilable(User) }
    attr_reader :user

    def initialize(business, **opts)
      @business = business
      @user = opts[:current_user]
      @token_scanning = SecretScanning::Features::Business::TokenScanning.new(business) unless business.nil?
    end

    def tabs
      tabs = []

      with_database_error_fallback do
        tabs << overview_tab
      end

      with_database_error_fallback do
        tabs << getting_started_tab if menu_accessible?(menu_item: :getting_started)
      end

      return tabs if @business&.being_created_from_coupon?

      with_database_error_fallback do
        tabs << organization_tab if menu_accessible?(menu_item: :organizations)
      end

      return tabs if @business&.upgrading_from_organization?

      with_database_error_fallback do
        tabs << people_tab if menu_accessible?(menu_item: :people)
      end

      with_database_error_fallback do
        if menu_accessible?(menu_item: :identity_provider)
          tabs << identity_provider_tab
        end
      end

      with_database_error_fallback do
        tabs << policies_tab if menu_accessible?(menu_item: :policies)
      end

      with_database_error_fallback do
        if menu_accessible? && GitHub.single_business_environment? && GitHub.dotcom_connection_enabled?
          tabs << ghes_github_connect_tab
        end
      end

      with_database_error_fallback do
        tabs << dotcom_github_connect_tab if menu_accessible?(menu_item: :github_connect)
      end

      with_database_error_fallback do
        tabs << code_security_tab if menu_accessible?(menu_item: :code_security)
      end

      with_database_error_fallback do
        tabs << billing_and_licensing_tab if menu_accessible?(menu_item: :billing)
      end

      with_database_error_fallback do
        tabs << settings_tab if menu_accessible?(menu_item: :settings)
      end

      with_database_error_fallback do
        tabs << compliance_tab if menu_accessible? && compliance_menu_item_available?
      end

      with_database_error_fallback do
        tabs << insights_tab if insights_tab_available?
      end

      tabs
    end

    def overview_tab
      Site::Header::UnderlineNavTab.new(
        text: "Overview",
        icon: :home,
        href: enterprise_path(business_slug),
        highlight: %i(
          business_overview
        ),
      )
    end

    def getting_started_tab
      Site::Header::UnderlineNavTab.new(
        text: @business&.trial_expired? ? "Upgrade to GitHub Enterprise" : "Getting started",
        href: enterprise_getting_started_path(business_slug),
        highlight: %i(
          business_getting_started
        ),
        icon: :"check-circle",
      )
    end

    def organization_tab
      Site::Header::UnderlineNavTab.new(
        text: "Organizations",
        href: enterprise_organizations_path(business_slug),
        highlight: %i(
          business_organizations
          business_member_organizations
          business_pending_organizations
          business_unowned_organizations
          business_invite_organizations
          business_new_organizations
        ),
        icon: :organization,
      )
    end

    def people_tab
      highlight = %i(
        business_people
        business_admins
        business_teams
        business_security_managers
        business_outside_collaborators
        business_suspended_members
        enterprise_role_management
        enterprise_role_assignments
        business_pending_members
        business_pending_collaborators
        business_pending_admins
        business_pending_invitations
        business_failed_invitations
        create_enterprise_teams
        edit_enterprise_teams
        business_organization_roles
      )

      Site::Header::UnderlineNavTab.new(
        text: "People",
        href: people_menu_items.flatten.first&.link_path,
        highlight: highlight,
        icon: :person,
      )
    end

    def policies_tab
      highlight = %i(
        business_member_privileges_settings
        business_custom_properties_settings
        business_repository_policies
        business_code_rulesets
        business_code_rule_insights
        business_code_rule_bypass_requests
        business_codespaces_settings
        business_copilot_settings
        business_projects_settings
        business_actions_settings
        business_actions_settings_runners
        business_actions_settings_add_new_runner
        business_actions_settings_runner_details
        business_actions_settings_runner_group
        business_actions_settings_runner_groups
        business_actions_settings_add_larger_runner
        business_actions_settings_edit_larger_runner
        business_actions_settings_larger_runner_details
        business_actions_settings_custom_images
        hosted_compute_networking
        business_admin_center_options
        business_advanced_security
        business_code_security_and_analysis
        business_actions_settings_hosted_runners
        business_personal_access_token_policy_settings
        sponsors_settings
        models_settings
      )

      Site::Header::UnderlineNavTab.new(
        text: "Policies",
        href: policies_menu_items.first&.link_path,
        highlight: highlight,
        icon: :law,
      )
    end

    def code_security_tab
      highlight = %i(
        business_security_center_overview
        business_security_center_risk
        business_security_center_coverage
        business_security_center_metrics_enablement
        business_code_scanning_metrics
        business_secret_scanning_metrics
        business_security_center_alerts_dependabot
        business_security_center_alerts_code_scanning
        business_security_center_alerts_secret_scanning
      )

      Site::Header::UnderlineNavTab.new(
        text: "Security",
        href: code_security_menu_items.flatten.first&.link_path,
        highlight: highlight,
        icon: :shield
      )
    end

    def billing_and_licensing_tab
      highlight = %i(
        business_billing_vnext_overview
        business_billing_vnext_usage
        business_billing_vnext_cost_centers
        business_billing_vnext_budgets_alerts
        business_licensing
        business_billing_vnext_payment_history
        business_billing_vnext_billing_contacts
        business_billing_vnext_marketplace_apps
        business_billing_vnext_billing_payment_information
        business_billing_vnext_sponsorships
        business_billing_vnext_past_invoices
      )

      Site::Header::UnderlineNavTab.new(
        text: "Billing and licensing",
        href: billing_menu_items.flatten.first&.link_path,
        highlight: highlight,
        icon: :"credit-card",
      )
    end

    def dotcom_github_connect_tab
      Site::Header::UnderlineNavTab.new(
        text: "GitHub Connect",
        href: enterprise_enterprise_installations_path(business_slug),
        icon: :plug,
        highlight: :business_connect_settings
      )
    end

    def ghes_github_connect_tab
      Site::Header::UnderlineNavTab.new(
        text: "GitHub Connect",
        href: admin_settings_dotcom_connection_enterprise_path(business_slug),
        icon: :plug,
        highlight: %i(
          business_connect_settings
          business_dotcom_connection
        )
      )
    end

    def settings_tab
      highlight = %i(
        business_profile_settings
        business_support_settings
        business_billing_settings
        business_packages_settings
        business_audit_log_settings
        business_audit_log_streams_settings
        business_audit_log_event_settings_settings
        business_audit_log_event_settings_export_logs
        retired_namespaces_settings
        hooks
        virtual_networks
        network_configurations
        business_security_analysis
        business_security_settings
        business_domains_settings
        business_license_settings
        business_custom_messages
        enterprise_licensing
        ssh_certificate_authorities
        ip_allowlist_entries
        business_insights_settings
        business_usage_settings
        linked_accounts_settings
        business_messages_settings
        integration_installations
        integrations_settings
        integrations
      )

      Site::Header::UnderlineNavTab.new(
        text: "Settings",
        href: settings_menu_items.flatten.first&.link_path,
        highlight: highlight,
        icon: :gear,
      )
    end

    def compliance_tab
      highlight = %i(
        business_compliance_settings
      )

      Site::Header::UnderlineNavTab.new(
        text: "Compliance",
        href: compliance_menu_items.flatten.first&.link_path,
        highlight: highlight,
        icon: :checklist,
      )
    end

    def identity_provider_tab
      link_path = if @business&.enterprise_managed_user_enabled?
        enterprise_single_sign_on_configuration_path(business_slug)
      else
        external_groups_enterprise_path(business_slug)
      end
      highlight = %i(
        external_groups
        linked_members
        linked_teams
        business_external_group_teams
        business_external_group_members
        single_sign_on_configuration
        edit_saml_configuration
        business_external_groups
      )

      Site::Header::UnderlineNavTab.new(
        text: "Identity provider",
        href: link_path,
        highlight: highlight,
        icon: :key,
      )
    end

    def insights_tab
      highlight = %i(
        business_actions_usage_metrics
        business_actions_performance_metrics
      )

      Site::Header::UnderlineNavTab.new(
        text: "Insights",
        href: insights_menu_items.flatten.first&.link_path,
        highlight: highlight,
        icon: :graph,
      )
    end

    sig { returns T::Boolean }
    memoize def scim_managed_enterprise?
      business&.enterprise_server_scim_enabled? ||
      business&.enterprise_managed_user_enabled?
    end

    private

    def business_slug
      business&.slug
    end

    def menu_accessible?(menu_item: nil)
      case menu_item
      when :getting_started
        return false if business_billing_manager?
        return false unless business_owner? || basic_user?
        with_database_error_fallback(fallback: false) do
          show_onboarding_experience? || show_org_upgrade_onboarding_experience?
        end
      when :organizations
        return false if basic_account? || basic_user?
        true if business_owner? || member_of_owned_org? || unaffiliated_member?
      when :people
        people_menu_items.flatten.present?
      when :policies
        return false if GitHub.billing_enabled? && @business&.downgraded_to_free_plan?
        policies_menu_items.flatten.present?
      when :github_connect
        return false if GitHub.single_business_environment?
        return false if basic_account?
        return false if GitHub.billing_enabled? && @business&.downgraded_to_free_plan?
        return false if @business&.metered_plan? && !@business.metered_ghes_eligible?
        business_owner? && (@business&.invoiced? || GitHub.multi_tenant_enterprise?)
      when :billing
        return false if !GitHub.billing_enabled?
        true if business_owner? || business_org_owner? || business_billing_manager?
      when :code_security
        return false if basic_account?
        return false if @business&.downgraded_to_free_plan?
        code_security_menu_items.flatten.present?
      when :settings
        settings_menu_items.present?
      when :identity_provider
        return false unless @business
        return false unless scim_managed_enterprise?
        return false if GitHub.billing_enabled? && @business.downgraded_to_free_plan?
        # Open SCIM is not supported in OIDC so we only need to check if the user can read SSO
        return @business.actor_can_read_sso?(@user) if @business.oidc_enabled?
        @business.actor_can_read_sso_or_scim?(@user)
      else
        return false if GitHub.billing_enabled? && @business&.downgraded_to_free_plan?
        business_owner?
      end
    end

    memoize def show_org_upgrade_onboarding_experience?
      return false unless @user
      return false unless @business&.upgraded_from_organization?
      return false if @business.downgraded_to_free_plan?
      @business.org_upgrade_onboarding_notice_set?(@user) && !@user.dismissed_business_notice?("org_upgrade_onboarding", business_id: @business.id)
    end

    memoize def show_onboarding_experience?
      return false if GitHub.single_business_environment?
      return false unless @user
      return false if @user.dismissed_business_notice?(BusinessesHelper::TRIAL_ONBOARDING_NOTICE_NAME, business_id: @business&.id) && !@business&.trial_expired?
      return false if @user.dismissed_business_notice?(BusinessesHelper::COPILOT_ONBOARDING_NOTICE_NAME, business_id: @business&.id)
      return true if @business&.seats_plan_basic?
      return false unless @business&.adminable_by?(@user)
      return true if @business.trial? && !@business.feature_enabled?(:digital_front_door_getting_started)

      false
    end

    memoize def basic_user?
      !@business&.user_on_seat_plan?(user)
    end

    memoize def member_of_owned_org?
      @business&.user_is_member_of_owned_org?(user)
    end

    memoize def unaffiliated_member?
      @business&.supports_unaffiliated_user_accounts? &&
      @business.exclusive_unaffiliated_member?(user)
    end

    memoize def show_code_security_settings_sub_menu_item?
      return false if basic_account?
      SecurityProduct::Permissions::BusinessAuthz.new(T.must(@business), actor: user).can_view_code_security_settings?
    end

    def compliance_menu_item_available?
      GitHub.multi_tenant_enterprise? || compliance_reports_available_for_account?(@business)
    end

    def insights_tab_available?
      return false if @business&.seats_plan_basic?
      @business&.actions_usage_metrics_enabled?(@user)
    end
  end
end
