# typed: true
# frozen_string_literal: true

module CommandPalette
  module PageNavigators
    class UserPageNavigator < PageNavigator
      # Returns the navigation items for a user

      def items
        return [] unless scope.user?

        items = [
          Result.jump_to(
            scope.user,
            priority: DEFAULT_PRIORITY + 10,
            context: context
          ).tap do |result|
            result.hint = "Jump to"
            result.group = "pages"
            result.typeahead = ""
            result.match_fields = ["Profile"]
          end,

        ]

        items += [
          Result.link_to(
            priority: DEFAULT_PRIORITY + 9,
            title: "Repositories",
            icon: "repo",
            path: user_path(scope.user, tab: "repositories"),
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY + 8,
            title: "Projects",
            icon: "table",
            path: user_path(scope.user, tab: "projects"),
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY + 7,
            title: "Packages",
            icon: "package",
            path: user_path(scope.user, tab: "packages"),
          ),
        ]

        items
      end
    end
  end
end
