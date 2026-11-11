# typed: true
# frozen_string_literal: true

class Organization
  class NavigationTabs < ContextRegion::LocalNavigation::NavigationTabs
    include GitHub::Memoizer
    include NavigationTabsInterface

    include IntegrationManagerHelper
    include InProductTargeting::ScanSecretLeaksConcern
    include UrlHelpers
    include UrlHelper

    TAB_METADATA = {
      overview: {
        icon: "home",
        label: "Overview",
        highlight: [:overview],
      },
      repositories: {
        icon: "repo",
        label: "Repositories",
        highlight: [:repositories],
      },
      discussions: {
        icon: "comment-discussion",
        label: "Discussions",
        highlight: [:discussions],
      },
      projects: {
        icon: "table",
        label: "Projects",
        highlight: [:projects],
      },
      packages: {
        icon: "package",
        label: "Packages",
        highlight: [:packages],
      },
      teams: {
        icon: "people",
        label: "Teams",
        highlight: [:teams],
      },
      people: {
        icon: "person",
        label: "People",
        highlight: [:people],
      },
      security: {
        icon: "shield",
        label: "Security",
        highlight: [:security],
      },
      insights: {
        icon: "graph",
        label: "Insights",
        highlight: [
          :insights,
          :copilot_metrics_insights,
        ],
      },
      sponsoring: {
        icon: "heart",
        label: "Sponsoring",
        highlight: [
          :sponsoring,
          :org_sponsoring_insights,
          :org_sponsoring_invoices,
          :org_sponsoring_settings,
        ],
      },
      settings: {
        icon: "gear",
        label: "Settings",
        highlight: [
          :settings,
          :organization_profile,
          :features,
          :organization_billing_settings,
          :roles,
          :member_privileges,
          :organization_team_settings,
          :organization_import_export_settings,
          :block_users,
          :interaction_limits,
          :code_review_limits,
          :moderators,
          :member_feature_requests,
          :repo_defaults,
          :repository_topics,
          :repo_rule_insights,
          :repo_rulesets,
          :org_rules_bypass_requests,
          :codespaces,
          :copilot,
          :actions,
          :stacks,
          :hooks,
          :organization_packages_settings,
          :organization_pages_settings,
          :organization_projects_settings,
          :organization_security,
          :security_analysis,
          :compliance,
          :verified_approved_domains,
          :secrets,
          :application_access_policy,
          :integration_installations,
          :personal_access_token_settings,
          :active_personal_access_tokens,
          :pending_requests,
          :personal_access_tokens_onboarding,
          :business_connect_settings,
          :settings_reminders,
          :org_announcements,
          :sponsors_log,
          :audit_log,
          :deleted_repositories,
          :applications_settings,
          :integrations,
          :publisher_settings,
          :custom_properties_for_repos,
          :custom_properties_for_orgs,
        ],
      },
      custom_models: {
        icon: "ai-model",
        label: "Fine-tuned models",
        highlight: [:fine_tuned_models],
      },
    }.freeze

    attr_reader :organization, :current_user

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
        custom_models_tab,
      ].compact
    end

    def tab_counts_url
      user_tab_counts_path(organization)
    end

    def overview_tab
      meta = TAB_METADATA[:overview]
      Site::Header::UnderlineNavTab.new(
        text: meta[:label],
        icon: meta[:icon],
        href: user_path(organization),
        highlight: meta[:highlight],
      )
    end

    def repositories_tab
      meta = TAB_METADATA[:repositories]
      Site::Header::UnderlineNavTab.new(
        text: meta[:label],
        icon: meta[:icon],
        href: org_repositories_path(organization),
        highlight: meta[:highlight],
        count: tab_count_for_react_payloads(:repositories),
        counter_arguments: { classes: "js-profile-repository-count" }
      )
    end

    def discussions_tab
      return unless GitHub.discussions_available_on_platform?
      return unless organization.present?
      return unless discussions_target_repo.present? && current_user_can_read_discussions_target_repo?

      meta = TAB_METADATA[:discussions]
      Site::Header::UnderlineNavTab.new(
        text: meta[:label],
        icon: meta[:icon],
        href: org_discussions_path(organization),
        highlight: meta[:highlight],
        count: tab_count_for_react_payloads(:discussions)
      )
    end

    def projects_tab
      return unless organization.organization_projects_enabled?

      meta = TAB_METADATA[:projects]
      Site::Header::UnderlineNavTab.new(
        text: meta[:label],
        icon: meta[:icon],
        href: projects_path(owner: organization),
        highlight: meta[:highlight],
        count: tab_count_for_react_payloads(:projects),
        counter_arguments: { classes: "js-profile-project-count" }
      )
    end

    def packages_tab
      return unless PackageRegistryHelper.show_packages?

      meta = TAB_METADATA[:packages]
      Site::Header::UnderlineNavTab.new(
        text: meta[:label],
        icon: meta[:icon],
        href: org_packages_path(organization),
        highlight: meta[:highlight],
        count: tab_count_for_react_payloads(:packages)
      )
    end

    def teams_tab
      return unless direct_or_team_member?

      meta = TAB_METADATA[:teams]
      Site::Header::UnderlineNavTab.new(
        text: meta[:label],
        icon: meta[:icon],
        href: teams_path(organization),
        highlight: meta[:highlight],
        count: tab_count_for_react_payloads(:teams),
        counter_arguments: { classes: "js-profile-team-count" }
      )
    end

    def people_tab
      return if billing_manager? && !direct_or_team_member?

      meta = TAB_METADATA[:people]
      Site::Header::UnderlineNavTab.new(
        text: meta[:label],
        icon: meta[:icon],
        href: org_people_path(organization),
        highlight: meta[:highlight],
        count: tab_count_for_react_payloads(:people),
        counter_arguments: { classes: "js-profile-member-count" }
      )
    end

    def insights_tab
      return unless (organization.has_insights_content_available_for?(current_user)) && org_member?

      meta = TAB_METADATA[:insights]
      Site::Header::UnderlineNavTab.new(
        text: meta[:label],
        icon: meta[:icon],
        href: org_insights_path(organization),
        highlight: meta[:highlight],
      )
    end

    def security_tab
      if ::SecretScanning::Features::Org::TokenScanning.new(organization).secret_risk_assessment_available?
        return unless direct_or_team_member?

        # Security center is not available for team orgs that have not enabled secret scanning on a non-public repo
        # That work is part of https://github.com/github/github/pull/366846

        if ::SecurityCenter::SecurityFeatures.security_center_available?(organization)
          return Site::Header::UnderlineNavTab.new(
            text: "Security",
            icon: :shield,
            href: security_center_overview_dashboard_path(organization),
            highlight: :security,
            popover_target: show_popover?,
          )
        end

        return unless ::SecretScanning::AccessControl::SecretRiskAssessments.new(organization).has_access_to_secret_risk_assessments?(current_user)
        return unless organization.plan.business? && organization.advanced_security_purchased?

        Site::Header::UnderlineNavTab.new(
          text: "Security",
          icon: :shield,
          href: security_center_assessments_path(organization),
          highlight: :security,
          popover_target: show_popover?,
        )
      else
        return unless direct_or_team_member?
        return unless ::SecurityCenter::SecurityFeatures.security_center_available?(organization)

        Site::Header::UnderlineNavTab.new(
          text: "Security",
          icon: :shield,
          href: security_center_overview_dashboard_path(organization),
          highlight: :security,
          popover_target: show_popover?,
        )
      end
    end

    def sponsoring_tab
      return unless GitHub.sponsors_enabled?
      return unless has_sponsored? || can_create_sponsor_invoices?

      meta = TAB_METADATA[:sponsoring]
      Site::Header::UnderlineNavTab.new(
        text: meta[:label],
        icon: meta[:icon],
        href: sponsoring_tab_url,
        highlight: meta[:highlight],
        count: sponsoring_count,
        counter_arguments: { classes: "js-profile-sponsoring-count" }
      )
    end

    def settings_tab
      return unless show_settings_tab?

      meta = TAB_METADATA[:settings]
      Site::Header::UnderlineNavTab.new(
        text: meta[:label],
        icon: meta[:icon],
        href: settings_org_profile_path(@organization),
        highlight: meta[:highlight],
      )
    end

    def custom_models_tab
      return unless show_custom_models_tab?

      meta = TAB_METADATA[:custom_models]
      Site::Header::UnderlineNavTab.new(
        text: meta[:label],
        icon: meta[:icon],
        href: custom_models_ga_ui_path(@organization),
        highlight: meta[:highlight],
      )
    end

    sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def popover
      nil
    end

    def repositories_count
      return nil if hide_repository_tab_count?
      visible_owned_repositories.count
    end

    def teams_count
      organization.visible_teams_for(current_user, with_business_teams: true).count
    end

    def people_count
      organization.visible_user_ids_for(current_user, limit: nil).count
    end

    def projects_count
      return 0 unless GitHub.projects_new_enabled?

      organization.accessible_memexes_scope(organization.memex_projects.open_projects, current_user).count
    end

    def discussions_count
      return 0 unless discussions_target_repo&.discussions_active?

      organization.visible_discussions_for(current_user).count
    end

    # Public: Get the packages count (always calculated, regardless of feature flag)
    #
    # An owner's packaged repo count tends to be much smaller than the overall repository count,
    # with large orgs on the scale of hundreds (with an outlier at 1800) vs in the hundreds of
    # thousands for overall repo count. By using this to reduce the list of all org repo IDs
    # accessible to the user, the IN clause for where(repository_id: ids) should never grow too large.
    #
    # Eg for orgs: https://data.githubapp.com/sql/share/c47bfa54
    def packages_count
      active_owned_packages = organization.packages.joins(:package_versions).merge(Registry::PackageVersion.not_deleted)
      package_repo_ids = active_owned_packages.distinct.pluck(:repository_id)

      visible_package_repo_ids = if current_user
        current_user.associated_repository_ids(repository_ids: package_repo_ids)
      else
        Repository.active.public_scope.where(id: package_repo_ids).pluck(:id)
      end

      visible_packages = active_owned_packages.where(repository_id: visible_package_repo_ids).distinct
      visible_packages.count
    end

    private

    def tab_count_for_react_payloads(tab_name)
      return nil unless FeatureFlag.vexi.enabled?(:global_nav_react, current_user, default: false)

      public_send("#{tab_name}_count")
    end

    def hide_repository_tab_count?
      organization.exceeds_owned_repo_limit?
    end

    # This is a feature-flagged optimization based on the results of the org_tab_count_private_ari experiment.
    #
    # When a user is viewing an org profile, we can use a more efficient scope to get visible repos, and
    # use it to generate a repo count and to further scope down the list of packages to count.
    #
    # Bots cannot currently use this optimization because their version of ARI doesn't support org scoping yet,
    # but the recent batched range optimization to org scoping for users may work for bots as well, at which
    # point this could become a more general optimization.
    #
    # :org_scoped_ari is a legacy feature flag meant to improve performance for specific users.
    memoize def visible_owned_repositories
      if FeatureFlag.vexi.enabled?(:org_scoped_ari, current_user, default: false) || organization.business.present?
        organization.
          visible_repositories_for_candidate(current_user).
          where(owner_id: organization.id)
      else
        org_repo_ids
      end
    end

    def org_repo_ids
      # The current user may be allowed to see this org's private repos if those repos are private forks
      # of repos owned by an org the user is an admin of. If this org has no private forks, there's
      # no need to check for this case, and if the user is an admin of this org they'll be able to
      # see those repos without a special oopfs check via their admin access.
      include_oopfs = !(organization.adminable_by?(current_user) || organization.repositories.forks.private_scope.none?)

      organization.visible_repositories_for(
        current_user,
        # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
        associated_repository_ids: current_user&.associated_repository_ids(include_oopfs: include_oopfs),
        # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
        limit_visible_internal_repos_to_org: true
      ).where(owner_id: organization.id).ids
    end

    def show_security_tab?
      can_access_security_center?(current_user, organization) || can_access_secret_risk_assessments?(current_user, organization)
    end

    def security_tab_path
      if can_access_security_center?(current_user, organization)
        security_center_overview_dashboard_path(organization)
      elsif can_access_secret_risk_assessments?(current_user, organization)
        security_center_assessments_path(organization)
      end
    end

    memoize def show_popover?
      false
    end

    def show_settings_tab?
      organization.can_view_organization_settings?(current_user)
    end

    def show_custom_models_tab?
      return false unless org_owner?
      current_user&.feature_flag_enabled_or_raise?(:copilot_custom_models_ga) || organization.feature_flag_enabled_or_raise?(:copilot_custom_models_ga) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
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
