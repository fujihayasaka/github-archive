# typed: true
# frozen_string_literal: true

class Business
  class NavigationTabs < ContextRegion::LocalNavigation::NavigationTabs
    include GitHub::Memoizer
    include UrlHelpers
    include EnterpriseNavigation::Links::All
    include EnterpriseNavigation::Links::SharedDependency
    include GitHub::ResilienceMixin
    include ComplianceReportHelper
    include BusinessesHelper

    # Tab metadata with icon, label, and highlight links
    TAB_METADATA = {
      overview: {
        icon: "home",
        label: "Overview",
        highlight: [
          :business_overview,
        ],
      },
      getting_started: {
        icon: "check-circle",
        label: "Getting started",
        highlight: [
          :business_getting_started,
        ],
      },
      organizations: {
        icon: "organization",
        label: "Organizations",
        highlight: [
          :business_organizations,
          :business_member_organizations,
          :business_pending_organizations,
          :business_unowned_organizations,
          :business_invite_organizations,
          :business_new_organizations,
          :business_organization_custom_properties_settings,
        ],
      },
      people: {
        icon: "person",
        label: "People",
        highlight: [
          :business_people,
          :business_admins,
          :business_teams,
          :business_security_managers,
          :business_outside_collaborators,
          :business_suspended_members,
          :enterprise_role_management,
          :enterprise_role_assignments,
          :business_pending_members,
          :business_pending_collaborators,
          :business_pending_admins,
          :business_pending_invitations,
          :business_failed_invitations,
          :create_enterprise_teams,
          :edit_enterprise_teams,
          :business_organization_roles,
        ],
      },
      identity_provider: {
        icon: "key",
        label: "Identity provider",
        highlight: [
          :external_groups,
          :linked_members,
          :linked_teams,
          :business_external_group_teams,
          :business_external_group_members,
          :single_sign_on_configuration,
          :edit_saml_configuration,
          :business_external_groups,
        ],
      },
      ai_controls: {
        icon: "copilot",
        label: "AI Controls",
        highlight: [
          :businesses_ai_controls_agents,
          :businesses_ai_controls_copilot,
          :businesses_ai_controls_mcp,
        ],
      },
      policies: {
        icon: "law",
        label: "Policies",
        highlight: [
          :business_member_privileges_settings,
          :business_custom_properties_settings,
          :business_repository_policies,
          :business_code_rulesets,
          :business_code_rule_insights,
          :business_code_rule_bypass_requests,
          :business_codespaces_settings,
          :business_sandbox_settings,
          :business_copilot_settings,
          :business_projects_settings,
          :business_actions_settings,
          :business_actions_rulesets,
          :business_actions_settings_runners,
          :business_actions_settings_add_new_runner,
          :business_actions_settings_runner_details,
          :business_actions_settings_runner_group,
          :business_actions_settings_runner_groups,
          :business_actions_settings_add_larger_runner,
          :business_actions_settings_edit_larger_runner,
          :business_actions_settings_larger_runner_details,
          :business_actions_settings_custom_images,
          :business_actions_settings_oidc_configuration,
          :hosted_compute_networking,
          :business_admin_center_options,
          :business_advanced_security,
          :business_license_policy_settings,
          :business_package_firewall_settings,
          :business_code_security_and_analysis,
          :business_actions_settings_hosted_runners,
          :business_personal_access_token_policy_settings,
          :sponsors_settings,
          :models_settings,
        ],
      },
      github_connect: {
        icon: "plug",
        label: "GitHub Connect",
        highlight: [
          :business_connect_settings,
          :business_dotcom_connection,
        ],
      },
      security: {
        icon: "shield",
        label: "Security",
        highlight: [
          :business_security_center_overview,
          :business_security_center_risk,
          :business_security_center_coverage,
          :business_security_center_metrics_enablement,
          :business_code_scanning_metrics,
          :business_secret_scanning_metrics,
          :business_security_center_alerts_dependabot,
          :business_security_center_alerts_dependabot_malware,
          :business_security_center_alerts_dependabot_vulnerabilities,
          :business_security_center_alerts_code_scanning,
          :business_security_center_alerts_secret_scanning,
          :business_security_center_public_monitoring,
          :business_security_center_dismissal_requests_secret_scanning,
          :business_security_center_dismissal_requests_code_scanning,
          :business_security_center_dismissal_requests_dependabot,
          :business_security_center_bypass_requests_license_compliance,
        ],
      },
      billing_and_licensing: {
        icon: "credit-card",
        label: "Billing and licensing",
        highlight: [
          :business_billing_vnext_overview,
          :business_billing_vnext_usage,
          :business_billing_vnext_cost_centers,
          :business_billing_vnext_budgets_alerts,
          :business_licensing,
          :business_billing_vnext_payment_history,
          :business_billing_vnext_billing_contacts,
          :business_billing_vnext_marketplace_apps,
          :business_billing_vnext_billing_payment_information,
          :business_billing_vnext_sponsorships,
          :business_billing_vnext_past_invoices,
          :business_billing_vnext_premium_requests_usage,
          :business_billing_vnext_ai_usage,
        ],
      },
      settings: {
        icon: "gear",
        label: "Settings",
        highlight: [
          :business_profile_settings,
          :business_support_settings,
          :business_billing_settings,
          :business_packages_settings,
          :business_audit_log_settings,
          :business_audit_log_streams_settings,
          :business_audit_log_event_settings_settings,
          :business_audit_log_event_settings_export_logs,
          :retired_namespaces_settings,
          :hooks,
          :virtual_networks,
          :network_configurations,
          :business_security_analysis,
          :business_security_settings,
          :business_domains_settings,
          :business_license_settings,
          :business_custom_messages,
          :enterprise_licensing,
          :ssh_certificate_authorities,
          :ip_allowlist_entries,
          :business_insights_settings,
          :business_usage_settings,
          :business_messages_settings,
          :integration_installations,
          :integrations_settings,
          :integrations,
        ],
      },
      compliance: {
        icon: "checklist",
        label: "Compliance",
        highlight: [
          :business_compliance_settings,
        ],
      },
      insights: {
        icon: "graph",
        label: "Insights",
        highlight: [
          :copilot_impact,
          :copilot_insights,
          :copilot_insights_code_generation,
          :business_actions_usage_metrics,
          :business_actions_performance_metrics,
        ],
      },
    }.freeze

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
      if business
        @token_scanning = SecretScanning::Features::Business::TokenScanning.new(business)
      end
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
        tabs << ai_controls_tab if menu_accessible?(menu_item: :ai_controls)
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
        tabs << compliance_tab if menu_accessible? && compliance_menu_item_available?
      end

      with_database_error_fallback do
        tabs << insights_tab if insights_tab_available?
      end

      with_database_error_fallback do
        tabs << settings_tab if menu_accessible?(menu_item: :settings)
      end

      tabs
    end

    def overview_tab
      record_tab_timing(:overview) do
        metadata = TAB_METADATA[:overview]
        Site::Header::UnderlineNavTab.new(
          text: metadata[:label],
          icon: metadata[:icon],
          href: enterprise_path(business_slug),
          highlight: metadata[:highlight],
        )
      end
    end

    def getting_started_tab
      record_tab_timing(:getting_started) do
        metadata = TAB_METADATA[:getting_started]
        Site::Header::UnderlineNavTab.new(
          text: @business&.trial_expired? ? "Upgrade to GitHub Enterprise" : metadata[:label],
          href: enterprise_getting_started_path(business_slug),
          highlight: metadata[:highlight],
          icon: metadata[:icon],
        )
      end
    end

    def organization_tab
      record_tab_timing(:organizations) do
        metadata = TAB_METADATA[:organizations]
        highlight = metadata[:highlight]

        if FeatureFlag.vexi.enabled?("glc_ia_enterprise_organizations_sidebar", @user, @business, default: false)
          highlight = highlight + [:business_member_privileges_settings, :business_projects_settings, :business_repository_policies, :business_custom_properties_settings, :business_code_rulesets, :business_code_rule_insights, :business_code_rule_bypass_requests]
        end

        Site::Header::UnderlineNavTab.new(
          text: metadata[:label],
          href: organizations_menu_items.flatten.first&.link_path,
          highlight: highlight,
          icon: metadata[:icon],
        )
      end
    end

    def people_tab
      record_tab_timing(:people) do
        metadata = TAB_METADATA[:people]
        highlight = metadata[:highlight]

        if FeatureFlag.vexi.enabled?("glc_ia_enterprise_people_sidebar", @user, @business, default: false)
          highlight = highlight + [:business_support_settings, :business_security_settings, :ssh_certificate_authorities, :ip_allowlist_entries]
        end

        Site::Header::UnderlineNavTab.new(
          text: metadata[:label],
          href: people_menu_items.flatten.first&.link_path,
          highlight: highlight,
          icon: metadata[:icon],
        )
      end
    end

    def policies_tab
      record_tab_timing(:policies) do
        metadata = TAB_METADATA[:policies]
        highlight = metadata[:highlight]

        if FeatureFlag.vexi.enabled?("glc_ia_enterprise_security_sidebar", @user, @business, default: false)
          highlight = highlight - [:business_code_security_and_analysis]
        end

        if FeatureFlag.vexi.enabled?("glc_ia_enterprise_organizations_sidebar", @user, @business, default: false)
          highlight = highlight - [:business_member_privileges_settings, :business_projects_settings, :business_repository_policies, :business_custom_properties_settings, :business_code_rulesets, :business_code_rule_insights, :business_code_rule_bypass_requests]
        end

        Site::Header::UnderlineNavTab.new(
          text: metadata[:label],
          href: policies_menu_items.first&.link_path,
          highlight: highlight,
          icon: metadata[:icon],
        )
      end
    end

    def ai_controls_tab
      record_tab_timing(:ai_controls) do
        metadata = TAB_METADATA[:ai_controls]
        Site::Header::UnderlineNavTab.new(
          text: metadata[:label],
          href: ai_controls_menu_items.flatten.first&.link_path,
          highlight: metadata[:highlight],
          icon: metadata[:icon]
        )
      end
    end

    def code_security_tab
      record_tab_timing(:code_security) do
        metadata = TAB_METADATA[:security]
        title = CodeQuality.combined_security_and_quality_navigation? ? "Security and quality" : metadata[:label]
        highlight = metadata[:highlight]

        if FeatureFlag.vexi.enabled?("glc_ia_enterprise_security_sidebar", @user, @business, default: false)
          highlight = highlight + [:business_code_security_and_analysis, :business_security_analysis]
        end

        Site::Header::UnderlineNavTab.new(
          text: title,
          href: code_security_menu_items.flatten.first&.link_path,
          highlight: highlight,
          icon: metadata[:icon]
        )
      end
    end

    def billing_and_licensing_tab
      record_tab_timing(:billing_and_licensing) do
        metadata = TAB_METADATA[:billing_and_licensing]

        Site::Header::UnderlineNavTab.new(
          text: metadata[:label],
          href: billing_menu_items.flatten.first&.link_path,
          highlight: metadata[:highlight],
          icon: metadata[:icon],
        )
      end
    end

    def dotcom_github_connect_tab
      record_tab_timing(:dotcom_github_connect) do
        metadata = TAB_METADATA[:github_connect]
        Site::Header::UnderlineNavTab.new(
          text: metadata[:label],
          href: enterprise_enterprise_installations_path(business_slug),
          icon: metadata[:icon],
          highlight: metadata[:highlight]
        )
      end
    end

    def ghes_github_connect_tab
      record_tab_timing(:ghes_github_connect) do
        metadata = TAB_METADATA[:github_connect]
        Site::Header::UnderlineNavTab.new(
          text: metadata[:label],
          href: admin_settings_dotcom_connection_enterprise_path(business_slug),
          icon: metadata[:icon],
          highlight: metadata[:highlight]
        )
      end
    end

    def settings_tab
      record_tab_timing(:settings) do
        metadata = TAB_METADATA[:settings]
        highlight = metadata[:highlight]

        if FeatureFlag.vexi.enabled?("glc_ia_enterprise_security_sidebar", @user, @business, default: false)
          highlight = highlight - [:business_security_analysis]
        end

        if FeatureFlag.vexi.enabled?("glc_ia_enterprise_people_sidebar", @user, @business, default: false)
          highlight = highlight - [:business_support_settings, :business_security_settings, :ssh_certificate_authorities, :ip_allowlist_entries]
        end

        Site::Header::UnderlineNavTab.new(
          text: metadata[:label],
          href: settings_menu_items.flatten.first&.link_path,
          highlight: highlight,
          icon: metadata[:icon],
        )
      end
    end

    def compliance_tab
      record_tab_timing(:compliance) do
        metadata = TAB_METADATA[:compliance]

        Site::Header::UnderlineNavTab.new(
          text: metadata[:label],
          href: compliance_menu_items.flatten.first&.link_path,
          highlight: metadata[:highlight],
          icon: metadata[:icon],
        )
      end
    end

    def identity_provider_tab
      record_tab_timing(:identity_provider) do
        metadata = TAB_METADATA[:identity_provider]
        link_path = if @business&.enterprise_managed_user_enabled?
          if @business.oidc_enabled? && !@business.actor_can_read_sso?(@user)
            # There are two tabs under identity provider: "Single sign-on configuration" and "Groups".
            # For OIDC enabled enterprises, the user must have read_enterprise_sso to view "Single sign-on configuration"
            # because there is no Open SCIM setting on that page (visibility controlled by read_enterprise_scim).
            # The user must have read_enterprise_scim to view "Groups". The "Single sign-on configuration" page should be the
            # default unless the user does not have read_enterprise_sso.
            external_groups_enterprise_path(business_slug)
          else
            enterprise_single_sign_on_configuration_path(business_slug)
          end
        else
          external_groups_enterprise_path(business_slug)
        end

        Site::Header::UnderlineNavTab.new(
          text: metadata[:label],
          href: link_path,
          highlight: metadata[:highlight],
          icon: metadata[:icon],
        )
      end
    end

    def insights_tab
      record_tab_timing(:insights) do
        metadata = TAB_METADATA[:insights]

        href = if show_copilot_impact_link?
          copilot_impact_menu_item.link_path
        else
          insights_menu_items.flatten.first&.link_path
        end

        Site::Header::UnderlineNavTab.new(
          text: metadata[:label],
          href: href,
          highlight: metadata[:highlight],
          icon: metadata[:icon],
        )
      end
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
        return false if basic_account?
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
      when :ai_controls
        return false unless show_ai_controls?(@business, copilot_context: copilot_context)
        ai_controls_menu_items.flatten.present?
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
      return true if @business.trial? && !@business.dfd_trial?

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
      insights_menu_items.any?
    end

    def entity_name
      "business"
    end
  end
end
