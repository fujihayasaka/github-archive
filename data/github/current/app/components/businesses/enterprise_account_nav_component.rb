# typed: true
# frozen_string_literal: true

# Want to add a new menu/sub-menu item, make some updates to an existing menu/sub-menu item or
# delete a menu/sub-menu item altogether? This is the place to do so. Any menu/sub-menu items
# defined in this component will automatically render correctly for both normal and responsive
# views.
#
# 1) To add a new menu item, define a method similar to organizations_menu_item or
#    people_menu_item, which returns a hash of the menu item's attributes:
#
#    a) link_name - a string containing the name to be displayed for the menu item.
#    b) link_path - a string containing the URL path of the menu item.
#    c) highlight - a symbol or array of symbols representing links to make the menu item
#       highlighted.
#    d) octicon - a string containing the name of the octicon to be displayed alongside the link
#       name of the menu item.
#    e) menu_test_selector - a string representing the menu item's test selector.
#    f) sub_menu_test_selector (optional) - a string representing the test selector of the nav
#       section of menu item's sub-menu items.
#    g) sub_menu_items (optional) - an array of hashes containing the menu item's sub menu items.
#
# 2) To add a new sub-menu item, define a method similar to members_sub_menu_item,
#    which returns a hash of the sub-menu item's attributes:
#
#    a) link_name - a string containing the name to be displayed for the sub-menu item.
#    b) link_path - a string containing the URL path of the sub-menu item.
#    c) highlight - a symbol or array of symbols representing links to make the sub-menu item
#       highlighted.
#
#    To ensure that the new sub-menu item is correctly shown as selected, update the parent menu's
#    highlight array to include the sub-menu item's highlight value(s).
#
# 3) To make some updates to an existing menu/sub-menu item, please refer to the guidelines above
#    for adding the same to enable you understand the right place to make the change(s).
#
# 4) To delete a menu/sub-menu item, locate its method and delete it. For a sub-menu item, please
#    make sure you delete it from its menu item's sub-menu items array. For a menu item, please
#    make sure you delete it from the menu item's array in the filtered_menu_items method.
#
# 5) If you want to control the visibility of a given menu item, please don't do so on the menu
#    item's method. Instead, update the filtered_menu_items method to achieve this. Also, if you
#    want to control the visibility of a given sub-menu item, locate or define the method for
#    constructing an array of its menu item's sub-menu items and control the visibility from there,
#    and don't do it from the sub-menu item's method.
#
# Please note that this guidelines are meant to keep the enterprise account navigation code clean
# and easier to maintain. If you have any questions, please contact us at #meao for
# further guidance.

class Businesses::EnterpriseAccountNavComponent < ApplicationComponent
  include BusinessesHelper
  include EnterpriseManagedUsersHelper
  include ResilienceHelper

  def initialize(business:, responsive: false, selected_link:)
    @business = business
    @responsive = responsive
    @selected_link = selected_link
    @token_scanning = SecretScanning::Features::Business::TokenScanning.new(business) unless business.nil?
  end

  private

  def render?
    @business.present?
  end

  def responsive?
    @responsive
  end

  def business_slug
    @business.slug
  end

  memoize def business_owner?
    @business.owner?(current_user)
  end

  memoize def business_org_owner?
    @business.user_is_owner_of_owned_org?(current_user)
  end

  memoize def business_billing_manager?
    @business.billing_manager?(current_user)
  end

  memoize def member_of_owned_org?
    @business.user_is_member_of_owned_org?(current_user)
  end

  memoize def basic_user?
    !@business.user_on_seat_plan?(current_user)
  end

  memoize def basic_account?
    @business.seats_plan_basic?
  end

  memoize def unaffiliated_member?
    @business.supports_unaffiliated_user_accounts? &&
    @business.exclusive_unaffiliated_member?(current_user)
  end

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  memoize def permission_grants
    navigation_permissions = [
      :read_enterprise_audit_logs
    ]
    Authz.domain.check_multiple_permissions(current_user, navigation_permissions, @business)
  end

  def vnext_migration_happened_in_last_thirty_days?
    return false if @business.customer&.is_vnext_native?

    @business.customer&.billed_via_billing_platform && @business.customer&.migration_happened_in_last_thirty_days?
  end

  def menu_accessible?(menu_item: nil)
    case menu_item
    when :getting_started
      return false if basic_user? && !business_owner?
      with_database_error_fallback(fallback: false) do
        show_onboarding_experience?(@business) || show_org_upgrade_onboarding_experience?(@business)
      end
    when :organizations
      return false if basic_account? || basic_user?
      true if business_owner? || member_of_owned_org? || unaffiliated_member?
    when :code_security
      return false if basic_account?
      return false if @business.downgraded_to_free_plan?
      code_security_menu_item.dig(:sub_menu_items).present? # Presence of sub menu items depends on the user's permissions
    when :billing
      return false if !GitHub.billing_enabled?
      true if @business.customer&.billed_via_billing_platform? && (
        business_owner? || business_org_owner? || business_billing_manager?)
    when :settings
      settings_menu_item.dig(:sub_menu_items).present? # Presence of sub menu items depends on the user's permissions
    when :github_connect
      return false if GitHub.single_business_environment?
      return false if basic_account?
      return false if GitHub.billing_enabled? && @business.downgraded_to_free_plan?
      return false if @business.metered_plan? && !@business.metered_ghes_eligible?
      business_owner? && (@business.invoiced? || GitHub.multi_tenant_enterprise?)
    when :people
      people_menu_item.dig(:sub_menu_items).present? # Presence of sub menu items depends on the user's permissions
    when :policies
      return false if GitHub.billing_enabled? && @business.downgraded_to_free_plan?
      policies_menu_item.dig(:sub_menu_items).present? # Presence of sub menu items depends on the user's permissions
    else
      return false if GitHub.billing_enabled? && @business.downgraded_to_free_plan?
      business_owner?
    end
  end

  def filtered_menu_items
    menu_items = []

    menu_items << overview_menu_item

    menu_items << getting_started_menu_item if menu_accessible?(menu_item: :getting_started)

    return menu_items if @business.being_created_from_coupon?

    menu_items << organizations_menu_item if menu_accessible?(menu_item: :organizations)

    return menu_items if @business.upgrading_from_organization?

    menu_items << people_menu_item if menu_accessible?(menu_item: :people)

    if menu_accessible? && scim_managed_enterprise?(@business)
      menu_items << identity_provider_menu_item
    end

    menu_items << github_insights_menu_item if menu_accessible? && GitHub.insights_available?
    menu_items << policies_menu_item if menu_accessible?(menu_item: :policies)

    if menu_accessible? && GitHub.single_business_environment? && GitHub.dotcom_connection_enabled?
      menu_items << ghes_github_connect_menu_item
    end

    menu_items << dotcom_github_connect_menu_item if menu_accessible?(menu_item: :github_connect)
    menu_items << code_security_menu_item if menu_accessible?(menu_item: :code_security)
    menu_items << billing_menu_item if menu_accessible?(menu_item: :billing)
    menu_items << settings_menu_item if menu_accessible?(menu_item: :settings)
    menu_items << compliance_menu_item if menu_accessible? && compliance_menu_item_available?

    menu_items
  end

  def overview_menu_item
    {
      link_name: "Overview",
      link_path: enterprise_path(business_slug),
      highlight: %i(
        business_overview
      ),
      octicon: "home",
      menu_test_selector: "overview-menu-item",
    }
  end

  def organizations_menu_item
    {
      link_name: "Organizations",
      link_path: enterprise_organizations_path(business_slug),
      highlight: %i(
        business_member_organizations
        business_pending_organizations
        business_unowned_organizations
      ),
      octicon: "organization",
      menu_test_selector: "organizations-menu-item",
    }
  end

  def getting_started_menu_item
    {
      link_name: @business.trial_expired? ? "Upgrade to GitHub Enterprise" : "Getting started",
      link_path: enterprise_getting_started_path(business_slug),
      highlight: %i(
        business_getting_started
      ),
      octicon: "check-circle",
      menu_test_selector: "getting-started-menu-item",
    }
  end

  def people_menu_item
    sub_menu_items = people_sub_menu_items

    # By including link_path we don't need to specify selected_link in the views by calling page_info
    highlight = sub_menu_items.flat_map { |item| item.fetch_values(:highlight, :link_path) }.concat(%i(
      business_pending_members
      business_pending_collaborators
      business_pending_admins
    ))

    {
      link_name: "People",
      link_path: sub_menu_items.first&.dig(:link_path),
      highlight:,
      octicon: "person",
      menu_test_selector: "people-menu-item",
      sub_menu_test_selector: "people-sub-menu-items",
      sub_menu_items:,
    }
  end

  def user_can_see_pending_or_failed_invitations?
    !GitHub.single_business_environment? &&
    !@business.enterprise_managed_user_enabled? &&
    (business_owner? || current_user.site_admin?)
  end

  def user_can_see_enterprise_organization_roles?
    (business_owner? || current_user.site_admin?) && @business.feature_enabled?(:enterprise_custom_organization_roles)
  end

  def user_can_see_custom_enterprise_roles?
    (business_owner? || current_user.site_admin?) && @business.feature_enabled?(:custom_enterprise_role_feature)
  end

  def people_sub_menu_items
    sub_menu_items = []
    if business_owner?
      sub_menu_items << members_sub_menu_item
      sub_menu_items << administrators_sub_menu_item
    end

    if business_owner? || member_of_owned_org?
      sub_menu_items << enterprise_teams_sub_menu_item if enterprise_teams_enabled?(@business)
      sub_menu_items << enterprise_security_managers_sub_menu_item if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
    end

    if business_owner?
      sub_menu_items << outside_collaborators_sub_menu_item if outside_collaborators_sub_menu_item_available?
      sub_menu_items << suspended_members_sub_menu_item if scim_managed_enterprise?(@business)
      sub_menu_items << custom_enterprise_roles_sub_menu_item if user_can_see_custom_enterprise_roles?
      sub_menu_items << enterprise_organization_roles_sub_menu_item if user_can_see_enterprise_organization_roles?
      sub_menu_items << pending_invitation_sub_menu_item if user_can_see_pending_or_failed_invitations?
      sub_menu_items << failed_invitation_sub_menu_item if user_can_see_pending_or_failed_invitations?
    end

    sub_menu_items
  end

  def members_sub_menu_item
    {
      link_name: "Members",
      link_path: people_enterprise_path(business_slug),
      highlight: %i(
        business_people
      )
    }
  end

  def administrators_sub_menu_item
    {
      link_name: "Administrators",
      link_path: enterprise_admins_path(business_slug),
      highlight: %i(
        business_admins
      )
    }
  end

  def pending_invitation_sub_menu_item
    {
      link_name: "Invitations",
      link_path: enterprise_pending_members_path(business_slug),
      highlight: %i(
        business_pending_invitations
      )
    }
  end

  def failed_invitation_sub_menu_item
    {
      link_name: "Failed invitations",
      link_path: enterprise_failed_invitations_path(business_slug),
      highlight: %i(
        business_failed_invitations
      )
    }
  end

  def custom_enterprise_roles_sub_menu_item
    {
      link_name: "Enterprise roles",
      link_path: enterprise_roles_path(business_slug),
      highlight: %i(
        enterprise_roles
      )
    }
  end

  def enterprise_organization_roles_sub_menu_item
    {
      link_name: "Organization roles",
      link_path: enterprise_organization_roles_path(business_slug),
      highlight: %i(
        business_organization_roles
      )
    }
  end

  def suspended_members_sub_menu_item
    {
      link_name: "Suspended",
      link_path: enterprise_suspended_members_path(business_slug),
      highlight: %i(
        business_suspended_members
      )
    }
  end

  def enterprise_teams_sub_menu_item
    {
      link_name: "Enterprise teams",
      link_path: enterprise_teams_path(business_slug),
      highlight: %i(
        business_teams
      )
    }
  end

  def enterprise_security_managers_sub_menu_item
    {
      link_name: "Security managers",
      link_path: enterprise_security_managers_path(business_slug),
      highlight: %i(business_security_managers),
    }
  end

  def outside_collaborators_sub_menu_item
    {
      link_name: outside_collaborators_verbiage(@business).capitalize,
      link_path: enterprise_outside_collaborators_path(business_slug),
      highlight: %i(
        business_outside_collaborators
      )
    }
  end

  def outside_collaborators_sub_menu_item_available?
    return false if scim_managed_enterprise?(@business) &&
                    !@business&.emu_repository_collaborators_enabled?
    return false if basic_account?
    true
  end

  def identity_provider_menu_item
    if @business.feature_enabled?(:move_emu_sso_configuration_page)
      sub_menu_items = identity_provider_sub_menu_items
      link_path = if @business.enterprise_managed_user_enabled?
        enterprise_single_sign_on_configuration_path(business_slug)
      else
        external_groups_enterprise_path(business_slug)
      end
      highlight = sub_menu_items.flat_map { |item| item.fetch_values(:highlight, :link_path) }.concat(%i(
          external_groups
          linked_members
          linked_teams
          business_external_group_teams
          business_external_group_members
      ))

      {
        link_name: "Identity provider",
        link_path: link_path,
        highlight: highlight,
        octicon: "key",
        menu_test_selector: "identity-provider-menu-item",
        sub_menu_test_selector: "identity-provider-sub-menu-items",
        sub_menu_items: sub_menu_items
      }
    else
      {
        link_name: "Identity provider",
        link_path: external_groups_enterprise_path(business_slug),
        highlight: %i(
          external_groups
          linked_members
          linked_teams
          business_external_group_teams
          business_external_group_members
        ),
        octicon: "key",
        menu_test_selector: "identity-provider-menu-item",
        sub_menu_test_selector: "identity-provider-sub-menu-items",
        sub_menu_items: [
          external_groups_sub_menu_item,
        ]
      }
    end
  end

  def identity_provider_sub_menu_items
    sub_menu_items = []
    sub_menu_items << sso_configuration_sub_menu_item if @business.enterprise_managed_user_enabled?
    sub_menu_items << external_groups_sub_menu_item
  end

  def external_groups_sub_menu_item
    {
      link_name: "Groups",
      link_path: external_groups_enterprise_path(business_slug),
      highlight: %i(
        external_groups
        linked_members
        linked_teams
      )
    }
  end

  def sso_configuration_sub_menu_item
    {
      link_name: "Single sign-on configuration",
      link_path: enterprise_single_sign_on_configuration_path(business_slug),
      highlight: %i(
        single_sign_on_configuration
        edit_saml_configuration
        saml_to_oidc_migration
      ),
    }
  end

  def github_insights_menu_item
    {
      link_name: "GitHub Insights",
      link_path: enterprise_insights_path(business_slug),
      highlight: :business_insights,
      octicon: "graph",
      menu_test_selector: "github-insights-menu-item"
    }
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def policies_menu_item
    {
      link_name: "Policies",
      link_path: policies_sub_menu_items.first&.dig(:link_path),
      highlight: %i(
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
      ),
      octicon: "law",
      menu_test_selector: "policies-menu-item",
      sub_menu_test_selector: "policies-sub-menu-items",
      sub_menu_items: policies_sub_menu_items,
    }
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  memoize def policies_sub_menu_items
    sub_menu_items = []

    if business_owner?
      sub_menu_items << repository_sub_menu_item if !basic_account? && @business.enterprise_rulesets_enabled?
      sub_menu_items << code_rules_sub_menu_item if !basic_account? && @business.enterprise_code_rulesets_enabled?
      sub_menu_items << code_rule_insights_sub_menu_item if !basic_account? && @business.enterprise_code_rulesets_enabled?
      sub_menu_items << code_rule_bypass_requests_sub_menu_item if !basic_account? && @business.enterprise_code_rulesets_enabled? && @business.delegated_bypass_enabled?
      sub_menu_items << business_properties_sub_menu_item if CustomProperties::Public.enterprise_properties_enabled?(@business) && !basic_account?
      sub_menu_items << member_privilege_sub_menu_item unless basic_account?
      sub_menu_items << codespaces_sub_menu_item if GitHub.codespaces_enabled? && !basic_account?

      if GitHub.copilot_enabled?
        # This ended up getting too complicated, so we're breaking it back down to basics.
        # We can do one of three things here based on the enterprise:
        # 1. show a link to the first run flow
        # 2. show a link to Copilot Enterprise Settings page (this is if they are a full GHEC enterprise who HAS configured things)
        # 3. don't show anything
        #
        # The logic breaks down like this:
        #
        # If they are a GHEC trial
        #   if they have CFB trial organization
        #     show copilot_sub_menu_item
        #   else
        #     hide menu
        #   end
        # elsif they are GHEC enterprise
        #   if they have a copilot configuration
        #     show copilot_sub_menu_item
        #   else
        #     show copilot_first_run_flow_sub_menu_item
        #   end
        # end
        if @business.trial? # this is a GHEC trial
          if helpers.active_copilot_trial(@business) # they have an active CFB trial
            sub_menu_items << copilot_sub_menu_item(standalone_business: false) # show sub menu, hiding organization settings
          end # else do nothing
        else # this is a full GHEC account
          if Copilot::Business.new(@business).eligible_for_first_run_flow?
            sub_menu_items << copilot_first_run_flow_sub_menu_item
          else
            sub_menu_items << copilot_sub_menu_item(standalone_business: @business.copilot_licensing_enabled?)
          end
        end
      end

      # Only Copilot policies are shown to basic accounts
      unless basic_account?
        sub_menu_items << actions_sub_menu_item if GitHub.actions_enabled?
        sub_menu_items << hosted_compute_networking_sub_menu_item if hosted_compute_networking_sub_menu_item_available?
        sub_menu_items << projects_sub_menu_item
        sub_menu_items << options_sub_menu_item if GitHub.single_business_environment?
        sub_menu_items << code_security_policies_sub_menu_item if show_code_security_policies_sub_menu_item?
        sub_menu_items << personal_access_token_policies_sub_menu_item if GitHub.patsv2_enabled?
        sub_menu_items << sponsors_sub_menu_item if show_sponsors_sub_menu_item?
        sub_menu_items << models_sub_menu_item if show_models_sub_menu_item?
      end
    else
      sub_menu_items << code_security_policies_sub_menu_item if show_code_security_policies_sub_menu_item?
    end

    sub_menu_items
  end

  def copilot_billable?
    with_database_error_fallback(fallback: false) do
      Copilot::Business.new(@business).copilot_billable?
    end
  end

  def member_privilege_sub_menu_item
    {
      link_name: "Member privileges",
      link_path: settings_member_privileges_enterprise_path(business_slug),
      highlight: :business_member_privileges_settings
    }
  end

  def business_properties_sub_menu_item
    {
      link_name: "Custom properties",
      link_path: settings_custom_properties_enterprise_path(business_slug),
      highlight: :business_custom_properties_settings,
    }
  end

  def repository_sub_menu_item
    {
      link_name: "Repository",
      link_path: settings_repository_policies_enterprise_path(business_slug),
      highlight: :business_repository_policies,
    }
  end

  def code_rules_sub_menu_item
    {
      link_name: "Code",
      link_path: settings_code_rules_enterprise_path(business_slug),
      highlight: :business_code_rulesets,
    }
  end

  def code_rule_insights_sub_menu_item
    {
      link_name: "Code insights",
      link_path: settings_code_rule_insights_enterprise_path(business_slug),
      highlight: :business_code_rule_insights,
    }
  end

  def code_rule_bypass_requests_sub_menu_item
    {
      link_name: "Code ruleset bypasses",
      link_path: settings_code_rules_bypass_requests_enterprise_path(business_slug),
      highlight: :business_code_rule_bypass_requests,
    }
  end

  def codespaces_sub_menu_item
    {
      link_name: "Codespaces",
      link_path: settings_codespaces_enterprise_path(business_slug),
      highlight: :business_codespaces_settings
    }
  end

  def copilot_first_run_flow_sub_menu_item
    {
      link_name: "Copilot",
      link_path: current_user.feature_enabled?(:copilot_purchase_flow_refresh) ? settings_copilot_enterprise_path(business_slug) : settings_copilot_first_run_flow_cta_enterprise_path(business_slug),
      highlight: :business_copilot_settings
    }
  end

  def copilot_sub_menu_item(standalone_business: false)
    {
      link_name: standalone_business ? "Copilot Business" : "Copilot",
      link_path: settings_copilot_enterprise_path(business_slug),
      highlight: :business_copilot_settings
    }
  end

  def actions_sub_menu_item
    {
      link_name: "Actions",
      link_path: settings_actions_enterprise_path(business_slug),
      highlight: %i(
        business_actions_settings
        business_actions_settings_runners
        business_actions_settings_add_new_runner
        business_actions_settings_runner_details
        business_actions_settings_runner_group
        business_actions_settings_runner_groups
        business_actions_settings_add_larger_runner
        business_actions_settings_edit_larger_runner
        business_actions_settings_larger_runner_details
        business_actions_settings_hosted_runners
        business_actions_settings_custom_images
      )
    }
  end

  def hosted_compute_networking_sub_menu_item
    {
      link_name: "Hosted compute networking",
      link_path: enterprise_hosted_compute_networking_path(business_slug),
      highlight: :hosted_compute_networking
    }
  end

  def hosted_compute_networking_sub_menu_item_available?
    return false if GitHub.single_business_environment?
    return false if @business.downgraded_to_free_plan?
    true
  end

  def projects_sub_menu_item
    {
      link_name: "Projects",
      link_path: settings_projects_enterprise_path(business_slug),
      highlight: :business_projects_settings,
    }
  end

  def options_sub_menu_item
    {
      link_name: "Options",
      link_path: admin_center_options_enterprise_path(business_slug),
      highlight: :business_admin_center_options
    }
  end

  sig { returns(T::Boolean) }
  private memoize def code_security_policies_sub_menu_item_available?
    return true if SecurityCenter::SecurityFeatures.dependabot_alerts_enabled_for_instance?
    return true if @business.advanced_security_purchased?
    return true if SecretScanning::Features::Business::TokenScanning.new(@business).feature_available?
    false
  end

  sig { returns(T::Boolean) }
  private memoize def show_code_security_policies_sub_menu_item?
    return false unless code_security_policies_sub_menu_item_available?
    SecurityProduct::Permissions::BusinessAuthz.new(@business, actor: current_user).can_view_code_security_policies?
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  private def code_security_policies_sub_menu_item
    {
      link_name: "Code security",
      link_path: settings_security_analysis_policies_enterprise_path(business_slug),
      highlight: :business_code_security_and_analysis
    }
  end

  def personal_access_token_policies_sub_menu_item
    {
      link_name: "Personal access tokens",
      link_path: settings_personal_access_tokens_enterprise_path(business_slug),
      highlight: :business_personal_access_token_policy_settings,
      release_phase: :ga
    }
  end

  sig { returns(T::Boolean) }
  def show_code_security_alerts_code_scanning_sub_menu_item?
    return false unless SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
    return false if GitHub.enterprise? && !@business.advanced_security_purchased?
    true
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  private def code_security_menu_item
    sub_menu_items = code_security_sub_menu_items

    # By including link_path we don't need to specify selected_link in the views by calling page_info
    highlight = sub_menu_items.flat_map { |item| item.fetch_values(:highlight, :link_path) }

    {
      link_name: "Code Security",
      link_path: sub_menu_items.first&.dig(:link_path),
      highlight:,
      octicon: "shield",
      menu_test_selector: "security-center-menu-item",
      sub_menu_test_selector: "security-center-sub-menu-items",
      sub_menu_items:,
    }
  end

  sig { returns(T::Array[T::Hash[Symbol, T.any(String, Symbol)]]) }
  private def code_security_sub_menu_items
    return [] unless business_owner? || member_of_owned_org?

    [].tap do |menu_items|
      menu_items << code_security_overview_sub_menu_item
      menu_items << code_security_risk_sub_menu_item
      menu_items << code_security_coverage_sub_menu_item
      menu_items << code_security_enablement_trends_sub_menu_item
      menu_items << code_security_metrics_code_scanning_sub_menu_item if show_code_security_alerts_code_scanning_sub_menu_item?
      menu_items << code_security_metrics_secret_scanning_sub_menu_item if @token_scanning.feature_available?
      menu_items << code_security_alerts_dependabot_sub_menu_item if ::SecurityCenter::SecurityFeatures.dependabot_alerts_enabled_for_instance?
      menu_items << code_security_alerts_code_scanning_sub_menu_item if show_code_security_alerts_code_scanning_sub_menu_item?
      menu_items << code_security_alerts_secret_scanning_sub_menu_item if @token_scanning.feature_available?
    end
  end

  sig { returns(T::Hash[Symbol, T.any(String, Symbol)]) }
  private def code_security_overview_sub_menu_item
    {
      link_name: "Overview",
      link_path: enterprise_security_center_overview_dashboard_path(business_slug),
      highlight: :business_security_center_overview,
    }
  end

  sig { returns(T::Hash[Symbol, T.any(String, Symbol)]) }
  private def code_security_risk_sub_menu_item
    {
      link_name: "Risk",
      link_path: security_center_risk_enterprise_path(business_slug),
      highlight: :business_security_center_risk
    }
  end

  sig { returns(T::Hash[Symbol, T.any(String, Symbol)]) }
  private def code_security_coverage_sub_menu_item
    {
      link_name: "Coverage",
      link_path: security_center_coverage_enterprise_path(business_slug),
      highlight: :business_security_center_coverage
    }
  end

  sig { returns(T::Hash[Symbol, T.any(String, Symbol)]) }
  private def code_security_enablement_trends_sub_menu_item
    {
      link_name: "Enablement trends",
      link_path: enterprise_security_center_metrics_enablement_path(business_slug),
      highlight: :business_security_center_metrics_enablement,
    }
  end

  sig { returns(T::Hash[Symbol, T.any(String, Symbol)]) }
  private def code_security_metrics_code_scanning_sub_menu_item
    {
      link_name: "CodeQL pull request alerts",
      link_path: enterprise_security_center_metrics_codeql_path(business_slug),
      highlight: :business_code_scanning_metrics,
    }
  end

  sig { returns(T::Hash[Symbol, T.any(String, Symbol)]) }
  private def code_security_metrics_secret_scanning_sub_menu_item
    {
      link_name: "Secret scanning metrics",
      link_path: enterprise_security_center_metrics_secret_scanning_path(business_slug),
      highlight: :business_secret_scanning_metrics,
    }
  end

  sig { returns(T::Hash[Symbol, T.any(String, Symbol)]) }
  private def code_security_alerts_secret_scanning_sub_menu_item
    {
      link_name: "Secret scanning alerts",
      link_path: security_center_alerts_secret_scanning_enterprise_path(business_slug),
      highlight: :business_security_center_alerts_secret_scanning,
    }
  end

  sig { returns(T::Hash[Symbol, T.any(String, Symbol)]) }
  private def code_security_alerts_dependabot_sub_menu_item
    {
      link_name: "Dependabot alerts",
      link_path: security_center_alerts_dependabot_enterprise_path(business_slug),
      highlight: :business_security_center_alerts_dependabot,
    }
  end

  sig { returns(T::Hash[Symbol, T.any(String, Symbol)]) }
  private def code_security_alerts_code_scanning_sub_menu_item
    {
      link_name: "Code scanning alerts",
      link_path: security_center_alerts_code_scanning_enterprise_path(business_slug),
      highlight: :business_security_center_alerts_code_scanning,
    }
  end

  def billing_menu_item
    {
      link_name: "Billing & Licensing",
      link_path: enterprise_billing_path(business_slug),
      highlight: %i(
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
      ),
      octicon: "credit-card",
      menu_test_selector: "billing-menu-item",
      sub_menu_test_selector: "billing-sub-menu-items",
      sub_menu_items: billing_sub_menu_items,
      release_phase: DateTime.now.utc >= Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE ? :ga : :beta, #TODO: replace with just :ga after GA date
    }
  end

  def billing_sub_menu_items
    sub_menu_items = [
      {
        link_name: "Overview",
        link_path: enterprise_billing_path(business_slug),
        highlight: :business_billing_vnext_overview,
      },
      {
        link_name: "Usage",
        link_path: enterprise_billing_usage_path(business_slug),
        highlight: :business_billing_vnext_usage,
      },
      {
        link_name: "Cost centers",
        link_path: enterprise_billing_cost_centers_path(business_slug),
        highlight: :business_billing_vnext_cost_centers,
      },
      {
        link_name: "Budgets and alerts",
        link_path: enterprise_billing_budgets_path(business_slug),
        highlight: :business_billing_vnext_budgets_alerts,
      }
    ]

    if add_licensing_menu_item?
      sub_menu_items << {
        link_name: "Licensing",
        link_path: enterprise_licensing_path(business_slug),
        highlight: :business_licensing
      }
    end

    if add_payment_information_menu_item?
      sub_menu_items << {
        link_name: "Payment information",
        link_path: enterprise_billing_payment_information_path(business_slug),
        highlight: :business_billing_vnext_billing_payment_information,
     }
    end

    if add_payment_history_menu_item?
      sub_menu_items << {
        link_name: "Payment history",
        link_path: enterprise_billing_payment_history_index_path(business_slug),
        highlight: :business_billing_vnext_payment_history,
      }
    end

    if add_past_invoices_menu_item?
      sub_menu_items << {
        link_name: "Past invoices",
        link_path: enterprise_billing_past_invoices_path(business_slug),
        highlight: :business_billing_vnext_past_invoices,
      }
    end

    if add_billing_contacts_menu_item?
      sub_menu_items << {
        link_name: "Billing contacts",
        link_path: enterprise_billing_contacts_path(business_slug),
        highlight: :business_billing_vnext_billing_contacts,
     }
    end

    if @business.billed_via_billing_platform? && business_budget_permission.show_marketplace_apps_tab?
      sub_menu_items << {
        link_name: "Marketplace apps",
        link_path: enterprise_billing_marketplace_apps_path(business_slug),
        highlight: :business_billing_vnext_marketplace_apps,
      }
    end

    if @business.billed_via_billing_platform? && business_budget_permission.show_sponsorships_tab?
      sub_menu_items << {
        link_name: "Sponsorships",
        link_path: enterprise_billing_sponsorships_path(business_slug),
        highlight: :business_billing_vnext_sponsorships,
      }
    end

    sub_menu_items
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def settings_menu_item
    {
      link_name: "Settings",
      link_path: settings_sub_menu_items.first&.dig(:link_path),
      highlight: %i(
        business_profile_settings
        business_support_settings
        business_billing_settings
        business_packages_settings
        business_audit_log_settings
        business_audit_log_stream_settings
        business_audit_log_event_settings_settings
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
        integrations
      ),
      octicon: "gear",
      menu_test_selector: "settings-menu-item",
      sub_menu_test_selector: "settings-sub-menu-items",
      sub_menu_items: settings_sub_menu_items,
    }
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  memoize def settings_sub_menu_items
    sub_menu_items = []

    if business_owner?
      sub_menu_items << profile_sub_menu_item

      if GitHub.billing_enabled?
        if !GitHub.proxima_billing_enabled?
          sub_menu_items << billing_sub_menu_item unless @business.disable_legacy_billing_page?
        end
        sub_menu_items << enterprise_licensing_sub_menu_item unless menu_accessible?(menu_item: :billing)
      end

      # Show Packages only when Packages v2 enabled and atleast one docker image exists
      sub_menu_items << packages_sub_menu_item if GitHub.subdomain_isolation? && GitHub.registry_v2_enabled_for_enterprise? && Registry::Package.any_package_exists("docker").count > 0
      sub_menu_items << license_sub_menu_item if GitHub.licensed_mode?
      sub_menu_items << security_sub_menu_item
      sub_menu_items << code_security_settings_sub_menu_item if show_code_security_settings_sub_menu_item?
      sub_menu_items << verified_domains_sub_menu_item if GitHub.verified_domains_enabled?
      sub_menu_items << audit_log_sub_menu_item
      sub_menu_items << retired_namespaces_sub_menu_item if GitHub.multi_tenant_enterprise?
      sub_menu_items << hooks_sub_menu_item if !basic_account?
      sub_menu_items << virtual_networks_sub_menu_item if !GitHub.single_business_environment? && @business.feature_enabled?(:codespaces_vnet_settings)
      sub_menu_items << network_configurations_sub_menu_item if network_configurations_sub_menu_item_available?
      sub_menu_items << github_insights_sub_menu_item if GitHub.insights_available?
      if @business.feature_enabled?(:enterprise_app_installation_management) || @business.feature_enabled?(:enterprise_owned_app_management)
        sub_menu_items << gh_apps_sub_menu_item
      end

      # add the repos-owned "announcement" item only on dotcom
      sub_menu_items << announcement_banner_sub_menu_item if !GitHub.single_business_environment?

      unless GitHub.single_business_environment?
        sub_menu_items << support_sub_menu_item
      end

      if GitHub.single_business_environment?
        sub_menu_items << custom_messages_sub_menu_item
        sub_menu_items << site_admin_sub_menu_item
      end

      sub_menu_items << linked_accounts_sub_menu_item if show_linked_accounts_sub_menu_item?
    elsif business_billing_manager?
      if GitHub.billing_enabled?
        sub_menu_items << billing_sub_menu_item unless @business.disable_legacy_billing_page?
        sub_menu_items << enterprise_licensing_sub_menu_item unless menu_accessible?(menu_item: :billing)
      end
      if @business.feature_enabled?(:use_biz_audit_log_fgp_ui)
        sub_menu_items.concat(settings_sub_menu_items_from_fgp_access)
      end
    else
      sub_menu_items << code_security_settings_sub_menu_item if show_code_security_settings_sub_menu_item?
      if @business.feature_enabled?(:use_biz_audit_log_fgp_ui)
        sub_menu_items.concat(settings_sub_menu_items_from_fgp_access)
      end
    end

    sub_menu_items
  end

  def profile_sub_menu_item
    {
      link_name: "Profile",
      link_path: settings_profile_enterprise_path(business_slug),
      highlight: :business_profile_settings,
    }
  end

  def billing_sub_menu_item
    {
      link_name: "Billing",
      link_path: settings_billing_enterprise_path(business_slug),
      highlight: :business_billing_settings,
      sub_menu_test_selector: "billing",
    }
  end

  def packages_sub_menu_item
    {
      link_name: "Packages",
      link_path: settings_packages_migration_enterprise_path(business_slug),
      highlight: :business_packages_settings
    }
  end

  def license_sub_menu_item
    {
      link_name: "License",
      link_path: settings_license_enterprise_path(business_slug),
      highlight: :business_license_settings
    }
  end

  def security_sub_menu_item
    {
      link_name: "Authentication security",
      link_path: settings_security_enterprise_path(business_slug),
      highlight: %i(
        business_security_settings
        ssh_certificate_authorities
        ip_allowlist_entries
      )
    }
  end


  sig { returns(T::Array[T.untyped]) }
  private memoize def settings_sub_menu_items_from_fgp_access
    sub_items = []
    sub_items << audit_log_sub_menu_item if permission_grants[:read_enterprise_audit_logs]

    sub_items
  end

  sig { returns(T::Boolean) }
  private memoize def show_code_security_settings_sub_menu_item?
    return false if basic_account?
    SecurityProduct::Permissions::BusinessAuthz.new(@business, actor: current_user).can_view_code_security_settings?
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  private def code_security_settings_sub_menu_item
    {
      link_name: "Code security",
      link_path: settings_security_analysis_enterprise_path(business_slug),
      highlight: :business_security_analysis_settings
    }
  end

  def verified_domains_sub_menu_item
    {
      link_name: "Verified & approved domains",
      link_path: settings_enterprise_domains_enterprise_path(business_slug),
      highlight: :business_domains_settings
    }
  end

  def audit_log_sub_menu_item
    {
      link_name: "Audit log",
      link_path: settings_audit_log_enterprise_path(business_slug),
      highlight: [:business_audit_log_settings, :business_audit_log_stream_settings, :business_audit_log_event_settings_settings]
    }
  end

  def retired_namespaces_sub_menu_item
    {
      link_name: "Retired namespaces",
      link_path: settings_retired_namespaces_enterprise_path(business_slug),
      highlight: :retired_namespaces_settings
    }
  end

  def hooks_sub_menu_item
    {
      link_name: "Hooks",
      link_path: hooks_enterprise_path(business_slug),
      highlight: :hooks
    }
  end

  def virtual_networks_sub_menu_item
    if @business.feature_enabled?(:codespaces_vnet_settings)
      {
        link_name: "Networking",
        link_path: settings_virtual_networks_path(business_slug),
        highlight: :virtual_networks
      }
    end
  end

  def network_configurations_sub_menu_item
    {
      link_name: "Hosted compute networking",
      link_path: settings_network_configurations_path(business_slug),
      highlight: :network_configurations
    }
  end

  def network_configurations_sub_menu_item_available?
    return false if @business.downgraded_to_free_plan?
    return false if GitHub.single_business_environment?
    true
  end

  def github_insights_sub_menu_item
    {
      link_name: "GitHub Insights",
      link_path: settings_enterprise_insights_path(business_slug),
      highlight: :business_insights_settings,
    }
  end

  def gh_apps_sub_menu_item
    {
      link_name: "GitHub Apps",
      link_path: gh_apps_sub_menu_item_link_path(business_slug),
      highlight: [:integrations, :integration_installations],
    }
  end

  private def gh_apps_sub_menu_item_link_path(business_slug)
    installations_enabled = @business.feature_enabled?(:enterprise_app_installation_management)
    apps_creation_enabled = @business.feature_enabled?(:enterprise_owned_app_management)

    # If both flippers are enabled, "GitHub Apps" should link to /settings/apps
    # If only the installations flipper is enabled, "GitHub Apps" should link to /settings/installations
    if apps_creation_enabled
      settings_apps_enterprise_path(business_slug)
    elsif installations_enabled
      settings_business_installations_enterprise_path(business_slug)
    else
      # This should never happen because the sub_menu_item is guarded behind
      # the flippers above, but let's be safe.
      "#"
    end
  end

  def dotcom_github_connect_menu_item
    items = nil
    if @business.feature_enabled?(:server_stats_graphs) && @business&.connected_enterprise_installations.any?
      items = [dotcom_github_connect_overview_sub_menu_item, dotcom_github_connect_graphs_sub_menu_item]
    end
    {
      link_name: "GitHub Connect",
      link_path: enterprise_enterprise_installations_path(business_slug),
      octicon: "plug",
      highlight: :business_connect_settings,
      menu_test_selector: "dotcom-github-connect-menu-item",
      sub_menu_test_selector: "dotcom-github-connect-sub-menu-items",
      sub_menu_items: items
    }
  end

  def dotcom_github_connect_overview_sub_menu_item
    {
      link_name: "Overview",
      link_path: enterprise_enterprise_installations_path(business_slug),
      highlight: :business_connect_graph
    }
  end

  def dotcom_github_connect_graphs_sub_menu_item
    {
      link_name: "Server Statistics",
      link_path: server_stats_enterprise_enterprise_installations_path(business_slug),
      highlight: :business_connect_graph
    }
  end

  def support_sub_menu_item
    {
      link_name: "Support",
      link_path: enterprise_support_index_path(business_slug),
      highlight: :business_support_settings
    }
  end

  def enterprise_licensing_sub_menu_item
    {
      link_name: "Enterprise licensing",
      link_path: enterprise_licensing_path(business_slug),
      highlight: :enterprise_licensing
    }
  end

  # this item is for the GHES announcement banner, it is separate from the repos-owned feature that exists on
  # dotcom. its text should be "Messages".
  def custom_messages_sub_menu_item
    {
      link_name: "Messages",
      link_path: custom_messages_enterprise_path(business_slug),
      highlight: :business_custom_messages
    }
  end

  def site_admin_sub_menu_item
    {
      link_name: "Site admin",
      link_path: stafftools_path
    }
  end

  def ghes_github_connect_menu_item
    {
      link_name: "GitHub Connect",
      link_path: admin_settings_dotcom_connection_enterprise_path(business_slug),
      octicon: "plug",
      menu_test_selector: "ghes-github-connect-menu-item"
    }
  end

  def compliance_menu_item_available?
    GitHub.multi_tenant_enterprise? || helpers.compliance_reports_available_for_account?(@business)
  end

  def compliance_menu_item
    {
      link_name: "Compliance",
      link_path: settings_compliance_enterprise_path(business_slug),
      highlight: %i(
        business_compliance_settings
      ),
      octicon: "checklist",
      menu_test_selector: "compliance-menu-item",
      sub_menu_test_selector: "compliance-sub-menu-items",
      sub_menu_items: compliance_sub_menu_items,
    }
  end

  def compliance_sub_menu_items
    items = []
    items << compliance_resources_sub_menu_item if GitHub.multi_tenant_enterprise? || helpers.compliance_reports_available_for_account?(@business)
    items
  end

  def compliance_resources_sub_menu_item
    {
      link_name: "Resources",
      link_path: settings_compliance_enterprise_path(business_slug),
      highlight: %i(
        business_compliance_settings
      )
    }
  end

  def show_linked_accounts_sub_menu_item?
    @business.enterprise_managed_user_enabled? && @business.feature_enabled?(:enterprise_linked_accounts)
  end

  def linked_accounts_sub_menu_item
    {
      link_name: "Linked accounts",
      link_path: settings_linked_accounts_enterprise_path(business_slug),
      highlight: :linked_accounts_settings,
    }
  end

  # this item is for the new repos-owned announcement banners, not for the GHES-specific implementation.
  # the text here should be "Announcement" to match the sidebar links in org and repo settings.
  def announcement_banner_sub_menu_item
    {
      link_name: "Announcement",
      link_path: edit_announcement_enterprise_path(business_slug),
      highlight: :business_messages_settings,
    }
  end

  def show_sponsors_sub_menu_item?
    return false unless GitHub.sponsors_enabled?

    @business.feature_enabled?(:sponsors_self_serve_enterprise)
  end

  def sponsors_sub_menu_item
    {
      link_name: "Sponsors",
      link_path: settings_sponsors_enterprise_path(business_slug),
      highlight: :sponsors_settings,
    }
  end

  def show_models_sub_menu_item?
    @business.enterprise_managed? && !@business.copilot_licensing_enabled?
  end

  def models_sub_menu_item
    {
      link_name: "Models",
      link_path: settings_models_enterprise_path(business_slug),
      highlight: :models_settings,
    }
  end

  def add_payment_history_menu_item?
    return false unless @business.billed_via_billing_platform?
    return false unless @business.owner?(current_user) || @business.billing_manager?(current_user)
    return false unless @business.can_self_serve? && !@business.invoiced?

    true
  end

  def add_past_invoices_menu_item?
    return false unless @business.billed_via_billing_platform?

    @business.show_past_invoices_tab?(current_user)
  end

  def add_billing_contacts_menu_item?
    return false unless @business.billed_via_billing_platform?
    return false unless @business.owner?(current_user) || @business.billing_manager?(current_user)

    true
  end

  def add_licensing_menu_item?
    return false unless @business.billed_via_billing_platform?
    return false unless @business.owner?(current_user) || @business.billing_manager?(current_user)

    true
  end

  def add_payment_information_menu_item?
    return false unless @business.billed_via_billing_platform?
    return false unless @business.owner?(current_user) || @business.billing_manager?(current_user)

    true
  end

  memoize def business_budget_permission
    T.let(Billing::Public::Budgets::Permission.new(@business, current_user), T.nilable(::Billing::Public::Budgets::Permission))
  end
end
