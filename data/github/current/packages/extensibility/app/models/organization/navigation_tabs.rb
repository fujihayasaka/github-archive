# typed: true
# frozen_string_literal: true

class Organization
  class NavigationTabs
    include IntegrationManagerHelper
    include UrlHelpers
    include UrlHelper

    attr_reader :organization, :current_user

    HIGHLIGHTS_FOR_SETTINGS = [
      :settings, :organization_profile, :features, :organization_billing_settings, :roles, :member_privileges,
      :organization_team_settings, :organization_import_export_settings, :block_users, :interaction_limits,
      :code_review_limits, :moderators, :member_feature_requests, :repo_defaults, :repository_topics,
      :repo_rule_insights, :repo_rulesets, :org_rules_bypass_requests, :codespaces, :copilot, :actions, :stacks, :hooks,
      :organization_packages_settings, :organization_pages_settings, :organization_projects_settings,
      :organization_security, :security_analysis, :compliance, :verified_approved_domains, :secrets,
      :application_access_policy, :integration_installations, :personal_access_token_settings,
      :active_personal_access_tokens, :pending_requests, :personal_access_tokens_onboarding,
      :business_connect_settings, :settings_reminders, :org_announcements, :sponsors_log, :audit_log, :deleted_repositories,
      :applications_settings, :integrations, :publisher_settings, :organization_custom_properties
    ]

    HIGHLIGHTS_FOR_SPONSORING = [
      :sponsoring,
      :org_sponsoring_insights,
      :org_sponsoring_invoices,
      :org_sponsoring_settings,
    ]

    def initialize(organization, **opts)
      @organization = organization
      @current_user = opts[:current_user]
    end

    def tabs
      [
        overview_tab,
        repositories_tab,
        discussions_tab,
        projects_tab,
        packages_tab,
        teams_tab,
        people_tab,
        security_tab,
        insights_tab,
        sponsoring_tab,
        settings_tab,
      ].compact
    end

    def tab_counts_url
      user_tab_counts_path(organization)
    end

    def overview_tab
      Site::Header::UnderlineNavTab.new(
        text: "Overview",
        icon: :home,
        href: user_path(organization),
        highlight: :overview,
      )
    end

    def repositories_tab

      Site::Header::UnderlineNavTab.new(
        text: "Repositories",
        icon: :repo,
        href: org_repositories_path(organization),
        highlight: :repositories,
        counter_arguments: { classes: "js-profile-repository-count" }
      )
    end

    def discussions_tab
      return unless GitHub.discussions_available_on_platform?
      return unless organization.present?
      return unless discussions_target_repo.present? && current_user_can_read_discussions_target_repo?

      Site::Header::UnderlineNavTab.new(
        text: "Discussions",
        icon: "comment-discussion",
        href: org_discussions_path(organization),
        highlight: :discussions
      )
    end

    def projects_tab
      return unless organization.organization_projects_enabled?

      Site::Header::UnderlineNavTab.new(
        text: "Projects",
        icon: :table,
        href: projects_path(owner: organization),
        highlight: :projects,
        counter_arguments: { classes: "js-profile-project-count" }
      )
    end

    def packages_tab
      return unless PackageRegistryHelper.show_packages?

      Site::Header::UnderlineNavTab.new(
        text: "Packages",
        icon: :package,
        href: org_packages_path(organization),
        highlight: :packages,
      )
    end

    def teams_tab
      return unless direct_or_team_member?

      Site::Header::UnderlineNavTab.new(
        text: "Teams",
        icon: :people,
        href: teams_path(organization),
        highlight: :teams,
        counter_arguments: { classes: "js-profile-team-count" }
      )
    end

    def people_tab
      return if billing_manager? && !direct_or_team_member?

      Site::Header::UnderlineNavTab.new(
        text: "People",
        icon: :person,
        href: org_people_path(organization),
        highlight: :people,
        counter_arguments: { classes: "js-profile-member-count" }
      )
    end

    def insights_tab
      return unless (organization.has_insights_content_available_for?(current_user)) && org_member?

      Site::Header::UnderlineNavTab.new(
        text: "Insights",
        icon: :graph,
        href: org_insights_path(organization),
        highlight: :insights,
      )
    end

    def security_tab
      return unless direct_or_team_member?
      return unless ::SecurityCenter::SecurityFeatures.security_center_available?(organization)

      Site::Header::UnderlineNavTab.new(
        text: "Security",
        icon: :shield,
        href: security_center_overview_dashboard_path(organization),
        highlight: :security,
      )
    end

    def sponsoring_tab
      return unless GitHub.sponsors_enabled?
      return unless has_sponsored? || can_create_sponsor_invoices?

      Site::Header::UnderlineNavTab.new(
        text: "Sponsoring",
        icon: :heart,
        href: sponsoring_tab_url,
        highlight: HIGHLIGHTS_FOR_SPONSORING,
        count: sponsoring_count,
        counter_arguments: { classes: "js-profile-sponsoring-count" }
      )
    end

    def settings_tab
      return unless show_settings_tab?

      Site::Header::UnderlineNavTab.new(
        text: "Settings",
        icon: :gear,
        href: settings_org_profile_path(@organization),
        highlight: HIGHLIGHTS_FOR_SETTINGS,
      )
    end

    private

    def show_settings_tab?
      return false unless organization.can_view_organization_settings?(current_user)
      true
    end

    def org_member?
      return @org_member if defined?(@org_member)
      @org_member = organization.member?(current_user)
    end

    def direct_or_team_member?
      return @direct_or_team_member if defined?(@direct_or_team_member)
      @direct_or_team_member = organization.direct_or_team_member?(current_user)
    end

    def billing_manager?
      return @billing_manager if defined?(@billing_manager)
      @billing_manager = organization.billing_manager?(current_user)
    end

    def org_owner?
      return @org_owner if defined?(@org_owner)
      @org_owner = organization.adminable_by?(current_user)
    end

    def discussions_target_repo
      return @discussions_target_repo if defined?(@discussions_target_repo)
      @discussions_target_repo = organization.discussion_repository&.repository
    end

    def current_user_can_read_discussions_target_repo?
      return @current_user_can_read_discussions_target_repo if defined?(@current_user_can_read_discussions_target_repo)
      @current_user_can_read_discussions_target_repo = discussions_target_repo&.readable_by?(current_user)
    end

    def sponsoring_count
      include_private = billing_manager? || org_member?
      organization.sponsoring_count(include_private: include_private)
    end

    def has_sponsored?
      include_private = billing_manager? || org_member?
      inactive_sponsoring_count = if !sponsoring_count.positive?
        organization.inactive_sponsoring_count(include_private: include_private)
      end

      sponsoring_count.positive? || inactive_sponsoring_count.positive?
    end

    def can_create_sponsor_invoices?
      return false unless organization.sponsors_customer_account.present?
      billing_manager? || org_owner?
    end

    def sponsoring_tab_url
      org_sponsoring_path(organization)
    end
  end
end
