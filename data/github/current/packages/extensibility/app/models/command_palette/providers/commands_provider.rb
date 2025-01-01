# typed: true
# frozen_string_literal: true

module CommandPalette
  module Providers
    class CommandsProvider < PrefetchedProvider
      include GistsHelper
      include ActionView::Helpers::AssetUrlHelper

      def self.modes
        [] # the mode is determined in the front-end provider's `enabledFor` method, depending on the query context
      end

      def self.type
        "commands"
      end

      def self.debounce
        0
      end

      def self.has_commands?
        true
      end

      def search(_)
        pseudo_commands + commands
      end

      def commands
        return [] unless current_user.commands_provider_enabled?
        Commands::CommandFinder::find_commands(context).map(&:to_result)
      end

      private

      # Command-like actions that link to pages rather than take action.
      # Eventually, these may be true commands. For now, this provides
      # some example commands.
      def pseudo_commands
        commands = []

        # Scope-specific create
        if scope.repository?
          if scope.repository.has_issues?
            commands << link_to_new("issue", choose_issue_path(scope.repository.owner, scope.repository), priority: 18)
          end
          if current_user.can_create_discussion?(scope.repository)
            commands << link_to_new("discussion", new_discussion_path(scope.repository.owner, scope.repository), priority: 16)
          end
          commands << link_to_new("file", new_file_path(scope.repository.owner, scope.repository, scope.repository.default_branch), priority: 15)
          commands << link_to_new("repository", new_repository_path, priority: 14)
          commands << Result.link_to(
            title: "Import repository",
            icon: "upload",
            path: new_repository_import_path,
            group: :global_commands,
            priority: 13
          ) if GitHub.porter_available?
        elsif scope.organization?
          if scope.organization.adminable_by?(current_user)
            commands << link_to_new("team", new_team_path(scope.organization), priority: 15)
            commands << link_to_new("repository", new_organization_repository_path(scope.organization), priority: 14)
            commands << Result.link_to(
              title: "Import repository",
              icon: "upload",
              path: new_repository_import_path,
              group: :global_commands,
              priority: 13
            ) if GitHub.porter_available?
          end
        else
          commands << link_to_new("repository", new_repository_path, priority: 15)
          commands << Result.link_to(
            title: "Import repository",
            icon: "upload",
            path: new_repository_import_path,
            group: :global_commands,
            priority: 14
          ) if GitHub.porter_available?
        end

        # Global create
        commands << link_to_new("organization", organizations_new_path, priority: 12) if GitHub.user_can_create_organizations?
        commands << link_to_new("gist", gist_root_url, priority: 11) if GitHub.gist_enabled?

        commands
      end

      def link_to_new(thing, path, priority: 10)
        Result.link_to(
          title: "New #{thing}",
          icon: "plus-circle",
          path: path,
          match_fields: ["Create #{thing}", "New #{thing}"],
          group: :global_commands,
          priority: priority
        )
      end
    end
  end
end
