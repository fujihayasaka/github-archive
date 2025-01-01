# typed: true
# frozen_string_literal: true

module CommandPalette
  module PageNavigators
    class RepoPageNavigator < PageNavigator
      # Returns the navigation items for a repository
      # Based off Repositories::UnderlineNavComponent

      def items
        return [] unless scope.repository?

        items = [
          Result.jump_to(
            scope.repository,
            priority: DEFAULT_PRIORITY + 20,
            context: context
          ).tap do |result|
            result.hint = "Jump to"
            result.group = "pages"
            result.typeahead = ""
            result.match_fields = ["Code"]
          end
        ]

        if scope.repository.has_issues?
          items << Result.link_to(
            priority: DEFAULT_PRIORITY + 10,
            title: "Issues",
            icon: "issue-opened",
            path: issues_path(scope.repository.owner, scope.repository),
          )
        end

        items << Result.link_to(
          priority: DEFAULT_PRIORITY + 9,
          title: "Pull requests",
          icon: "git-pull-request",
          path: pull_requests_path(scope.repository.owner, scope.repository),
        )

        if scope.repository.discussions_active?
          items << Result.link_to(
            priority: DEFAULT_PRIORITY + 8,
            title: "Discussions",
            icon: "comment-discussion",
            path: discussions_path(scope.repository.owner, scope.repository),
          )
        end

        if (GitHub.actions_enabled? && !scope.repository.actions_disabled?) || (!GitHub.actions_enabled? && GitHub.actions_packages_enterprise_setup_pending?)
          items << Result.link_to(
            priority: DEFAULT_PRIORITY + 7,
            title: "Actions",
            icon: "play",
            path: actions_path(scope.repository.owner, scope.repository),
          )
        end

        if scope.repository.repository_projects_enabled?
          items << Result.link_to(
            priority: DEFAULT_PRIORITY + 6,
            title: "Projects",
            icon: "table",
            path: repo_projects_path(scope.repository.owner, scope.repository),
          )
        end

        if scope.repository.merge_queue_enabled?
          merge_queue = scope.repository.default_merge_queue

          if merge_queue
            items << Result.link_to(
              priority: DEFAULT_PRIORITY + 5,
              title: "Merge queue",
              icon: "git-merge",
              path: merge_queue_path(scope.repository.owner, scope.repository, merge_queue.branch),
            )
          end
        end

        if scope.repository.show_wiki?(current_user)
          items << Result.link_to(
            priority: DEFAULT_PRIORITY + 5,
            title: "Wiki",
            icon: "book",
            path: wikis_path(scope.repository.owner, scope.repository),
          )
        end

        items << Result.link_to(
          priority: DEFAULT_PRIORITY + 4,
          title: "Security",
          icon: "shield",
          path: repository_security_overview_path(scope.repository.owner, scope.repository),
        )

        items += insights_navigation_item

        items += settings_navigation_item

        items.each do |result|
          result.object = scope.repository
        end

        items
      end

      def insights_navigation_item
        return [] if scope.repository.advisory_workspace?

        path = if scope.repository.plan_supports?(:insights)
          gh_pulse_path(scope.repository)
        elsif GitHub.dependency_graph_enabled?
          gh_network_dependencies_path(scope.repository)
        end

        return [] unless path.present?

        [
          Result.link_to(
            priority: DEFAULT_PRIORITY + 3,
            title: "Insights",
            icon: "graph",
            path: path,
          )
        ]
      end

      def settings_navigation_item
        show_settings = if scope.repository.show_config_authzd_enabled?
          scope.repository.batched_layout_authzd_permissions(current_user, :show_config)
        else
          if scope.repository.advisory_workspace?
            false
          else
            permission = scope.repository.async_action_or_role_level_for(current_user, include_custom_roles: false).sync
            [:maintain, :admin].include?(permission)
          end
        end

        if show_settings
          [
            Result.link_to(
              priority: DEFAULT_PRIORITY + 2,
              title: "Settings",
              icon: "gear",
              path: edit_repository_path(scope.repository.owner, scope.repository),
            )
          ]
        elsif scope.repository.owner.is_a?(Organization) && SecurityProduct::Permissions::RepoAuthz.new(scope.repository, actor: current_user).can_manage_repo_security_products?
          [
            Result.link_to(
              priority: DEFAULT_PRIORITY,
              title: "Settings",
              icon: "gear",
              path: repository_security_and_analysis_path(scope.repository.owner, scope.repository),
            )
          ]
        else
          []
        end
      end
    end
  end
end
