# typed: strict
# frozen_string_literal: true

module GlobalNavigation
  class CreateMenuPayload < BasePayload
    include ApplicationHelper

    delegate :request, to: :helpers

    sig { returns(T::Boolean) }
    attr_reader :user_can_create_organizations

    sig { returns(T::Boolean) }
    attr_reader :memex_enabled

    sig { returns(T::Boolean) }
    attr_reader :show_issue_create_link

    alias :user_can_create_organizations? :user_can_create_organizations
    alias :memex_enabled? :memex_enabled
    alias :show_issue_create_link? :show_issue_create_link

    sig { override.returns(String) }
    def route_id
      "createMenuRoute"
    end

    sig do
      params(
        current_user: T.nilable(User),
        current_repository: T.nilable(Repository),
        current_organization: T.nilable(Organization),
        user_can_create_organizations: T::Boolean,
        memex_enabled: T::Boolean,
        show_issue_create_link: T::Boolean,
        source: String,
        current_copilot_user: T.nilable(T.any(Copilot::User, Copilot::Public::User))
      ).void
    end
    def initialize(
      current_user:,
      current_repository:,
      current_organization:,
      user_can_create_organizations:,
      memex_enabled:,
      show_issue_create_link:,
      source:,
      current_copilot_user: nil
    )
      super(
        current_user: current_user,
        current_copilot_user: current_copilot_user,
        current_organization: current_organization,
        current_repository: current_repository,
        source: source
      )
      @user_can_create_organizations = T.let(user_can_create_organizations, T::Boolean)
      @memex_enabled = T.let(memex_enabled, T::Boolean)
      @show_issue_create_link = T.let(show_issue_create_link, T::Boolean)
    end

    sig { override.returns(T::Hash[T.untyped, T.untyped]) }
    memoize def payload
      GitHub.dogstats.time("global_navigation.create_menu", tags: tracking_tags) do
        {
          showCreateRepo: show_new_repository_link?,
          showImportRepo: show_repository_import_link?,
          showCodespaces: show_new_codespace_link?,
          showSpark: show_spark_link?,
          showCodingAgent: show_coding_agent_link?,
          showGist: show_new_gist_link?,
          showCreateOrg: user_can_create_organizations?,
          showCreateProject: show_project_link?,
          showCreateLegacyProject: show_legacy_project_link?,
          showCreateIssue: show_issue_create_link?,
          createProjectUrl: project_path,
          org: org_for_props,
          owner: current_repository ? T.must(current_repository).owner_display_login : nil,
          repo: current_repository&.readable_by?(current_user) ? T.must(current_repository).name : nil,
        }
      end
    end

    sig { returns(T.nilable(T::Boolean)) }
    memoize def show_org_links?
      organization && !organization&.new_record? && organization&.adminable_by?(current_user)
    end

    sig { returns(T.nilable(T::Boolean)) }
    memoize def show_repository_import_link?
      GitHub.porter_available? && show_new_repository_link?
    end

    sig { returns(T::Boolean) }
    memoize def show_new_codespace_link?
      !!GitHub.codespaces_enabled?
    end

    sig { returns(T.nilable(T::Boolean)) }
    memoize def show_new_gist_link?
      GitHub.gist_enabled?(current_user)
    end

    sig { returns(T.nilable(T::Boolean)) }
    def show_spark_link?
      # It's not as nice of an experience, but we skip FF checks on org + enterprise
      # because we can't safely touch the copilot cluster from the global header.
      # This is an edge case only until we've rolled out CB, so we'll live with it.
      GitHub.copilot_enabled? && current_user&.spark_enabled?(check_hierarchy: false)
    end

    sig { returns(T.nilable(T::Boolean)) }
    def show_coding_agent_link?
      return false unless GitHub.copilot_enabled? && current_user.present?
      return false unless T.must(current_user).feature_flag_enabled?(:coding_agent_add_menu_link, default: false)

      copilot_user = current_copilot_user_v2
      return false unless copilot_user

      copilot_user.swe_agent_enabled?
    end

    sig { returns(T::Boolean) }
    memoize def show_new_repository_link?
      return true if GitHub.enterprise?
      !current_user&.enterprise_managed_business&.seats_plan_basic?
    end

    sig { returns(T.nilable(Organization)) }
    memoize def organization
      current_organization || repository_organization
    end

    sig { returns(T::Boolean) }
    memoize def show_project_link?
      memex_enabled? && in_user_project_context?
    end

    sig { returns(T::Boolean) }
    memoize def show_legacy_project_link?
      !show_project_link? && in_user_project_context?
    end

    sig { params(event_name: T.untyped).returns(T::Hash[String, T.untyped]) }
    def tracking_data_attributes(event_name)
      analytics_click_attributes(category: "SiteHeaderComponent", action: "add_dropdown", label: event_name)
    end

    sig { returns(String) }
    def project_path
      Rails.application.routes.url_helpers.user_path(current_user, params: { tab: :projects })
    end

    private

    sig { returns(T.nilable(Organization)) }
    memoize def repository_organization
      current_repository && T.must(current_repository).owner&.organization? ? T.cast(T.must(current_repository).owner, Organization) : nil
    end

    sig { returns(T::Boolean) }
    memoize def in_user_project_context?
      !current_repository && !organization
    end

    sig { returns(T.nilable(T::Hash[String, T.untyped])) }
    memoize def org_for_props
      return nil unless show_org_links?

      {
        login: organization&.display_login,
        addWord: invite_or_add_action_word(enterprise_managed: organization&.enterprise_managed_user_enabled?),
      }
    end
  end
end
