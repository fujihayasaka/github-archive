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
          createRepo: show_new_repository_link?,
          importRepo: show_repository_import_link?,
          codespaces: show_new_codespace_link?,
          gist: show_new_gist_link?,
          createOrg: user_can_create_organizations?,
          createProject: show_project_link?,
          createProjectUrl: project_path,
          createLegacyProject: show_legacy_project_link?,
          createIssue: show_issue_create_link?,
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

      def legacy_project_path
        Rails.application.routes.url_helpers.new_project_path
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
