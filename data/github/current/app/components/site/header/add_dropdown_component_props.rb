# typed: true
# frozen_string_literal: true

module Site
  module Header
    class AddDropdownComponentProps
      include GistsHelper
      include GitHub::Memoizer
      include AnalyticsHelper
      include ApplicationHelper

      delegate :request, to: :helpers

      attr_reader :current_user, :repository
      attr_reader :user_can_create_organizations, :memex_enabled
      alias :user_can_create_organizations? :user_can_create_organizations
      alias :memex_enabled? :memex_enabled

      def initialize(
        current_user:,
        current_organization:,
        repository:,
        user_can_create_organizations:,
        memex_enabled:,
        show_issue_create_link:
      )
        @current_user = current_user
        @current_organization = current_organization
        @repository = repository
        @user_can_create_organizations = user_can_create_organizations
        @memex_enabled = memex_enabled
        @show_issue_create_link = show_issue_create_link
      end

      def create_menu_props
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
          owner: repository ? repository.owner_display_login : nil,
          repo: repository&.readable_by?(current_user) ? repository.name : nil,
        }
      end

      memoize def show_org_links?
        organization && !organization.new_record? && organization.adminable_by?(current_user)
      end

      memoize def show_repository_import_link?
        GitHub.porter_available? && show_new_repository_link?
      end

      def show_issue_create_link?
        @show_issue_create_link
      end

      memoize def show_new_codespace_link?
        GitHub.codespaces_enabled?
      end

      memoize def show_new_gist_link?
        GitHub.gist_enabled?(current_user)
      end

      def show_spark_link?
        # It's not as nice of an experience, but we skip FF checks on org + enterprise
        # because we can't safely touch the copilot cluster from the global header.
        # This is an edge case only until we've rolled out CB, so we'll live with it.
        GitHub.copilot_enabled? && current_user&.spark_enabled?(check_hierarchy: false)
      end

      def show_coding_agent_link?
        GitHub.copilot_enabled? && current_user.present? && current_user.feature_flag_enabled?(:coding_agent_add_menu_link, default: false) && Copilot::Public::User.new(current_user).swe_agent_enabled?
      end

      memoize def show_new_repository_link?
        return true if GitHub.enterprise?
        !current_user&.enterprise_managed_business&.seats_plan_basic?
      end

      memoize def organization
        @current_organization || repository_organization
      end

      memoize def show_project_link?
        memex_enabled? && in_user_project_context?
      end

      memoize def show_legacy_project_link?
        !show_project_link? && in_user_project_context?
      end

      def tracking_data_attributes(event_name)
        analytics_click_attributes(category: "SiteHeaderComponent", action: "add_dropdown", label: event_name)
      end

      def project_path
        Rails.application.routes.url_helpers.user_path(current_user, params: { tab: :projects })
      end

      private

      memoize def repository_organization
        repository && repository.owner.organization? && repository.owner
      end

      memoize def in_user_project_context?
        !repository && !organization
      end

      memoize def org_for_props
        return nil unless show_org_links?

        {
          login: organization.display_login,
          addWord: invite_or_add_action_word(enterprise_managed: organization.enterprise_managed_user_enabled?),
        }
      end
    end
  end
end
