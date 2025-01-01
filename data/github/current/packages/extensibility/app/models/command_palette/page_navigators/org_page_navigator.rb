# typed: true
# frozen_string_literal: true

module CommandPalette
  module PageNavigators
    class OrgPageNavigator < PageNavigator
      include IntegrationManagerHelper

      # Returns the navigation items for an organization
      # Based off Organizations::HeaderNavComponent

      def items
        return [] unless scope.organization?
        items = []
        items << Result.jump_to(
          scope.organization,
          priority: DEFAULT_PRIORITY,
          context: context
        ).tap do |result|
          result.hint = "Jump to"
          result.group = "pages"
          result.typeahead = ""
          result.match_fields = ["Profile"]
        end

        repos_path = org_repositories_path(scope.organization)

        items += [
          Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Repositories",
            icon: "repo",
            path: repos_path,
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Packages",
            icon: "package",
            path: org_packages_path(scope.organization),
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "People",
            icon: "person",
            path: org_people_path(scope.organization),
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Teams",
            icon: "people",
            path: teams_path(scope.organization),
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Projects",
            icon: "table",
            path: org_projects_path(scope.organization),
          ),
        ]

        if include_discussions?
          items << Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Discussions",
            icon: "comment-discussion",
            path: org_discussions_path(scope.organization),
          )
        end

        if include_sponsoring?
          items << Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Sponsoring",
            icon: "heart",
            path: org_sponsoring_path(scope.organization),
          )
        end

        items += org_settings_item

        items.each do |result|
          result.object = scope.organization
        end

        items
      end

      def include_sponsoring?
        return false unless GitHub.sponsors_enabled?
        org = scope.organization
        include_private = org.private_sponsor_identity_visible_to?(current_user)
        org.sponsoring_count(include_private: include_private) > 0
      end

      def include_discussions?
        return false unless GitHub.discussions_available_on_platform?
        target_repo.present? && target_repo.readable_by?(current_user)
      end

      def target_repo
        return @target_repo if defined?(@target_repo)
        @target_repo = scope.organization&.discussion_repository&.repository
      end

      def org_admin?
        return @org_admin if defined?(@org_admin)
        @org_admin = scope.organization.adminable_by?(current_user)
      end

      def billing_manager?
        return @billing_manager if defined?(@billing_manager)
        @billing_manager = scope.organization.billing_manager?(current_user)
      end

      def org_settings_item
        is_app_manager = manages_any_integration?(user: current_user, organization: scope.organization)

        return [] unless org_admin? || billing_manager? || is_app_manager

        path = if org_admin?
          settings_org_profile_path(scope.organization)
        elsif billing_manager?
          settings_org_billing_path(scope.organization)
        elsif is_app_manager
          settings_org_apps_path(scope.organization)
        end

        [
          Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Settings",
            icon: "gear",
            path: path,
          ),
        ]
      end
    end
  end
end
