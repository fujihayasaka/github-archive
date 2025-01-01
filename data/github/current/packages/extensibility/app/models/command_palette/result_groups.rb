# typed: true
# frozen_string_literal: true

module CommandPalette
  class ResultGroups
    GROUPS = {
      top: {
        title: "Top result",
        global_sort: 0,
        user_sort: 0,
        repo_sort: 0
      },
      default: {
        global_sort: 1,
        user_sort: 1,
        repo_sort: 1,
        limits: {
          static_items_page: 50
        }
      },
      commands: {
        hint: "Type > to filter",
        global_sort: 0,
        user_sort: 0,
        repo_sort: 0,
        limits: {
          static_items_page: 50,
          issue: 50,
          pull_request: 50,
          discussion: 50
        }
      },
      global_commands: {
        hint: "Type > to filter",
        global_sort: 0,
        user_sort: 0,
        repo_sort: 0,
        limits: {
          issue: 0,
          pull_request: 0,
          discussion: 0
        }
      },
      this_page: {
        global_sort: 0,
        user_sort: 0,
        repo_sort: 0
      },
      pages: {
        global_sort: 1,
        user_sort: 1,
        repo_sort: 0,
        limits: {
          repository: 10
        }
      },
      access_policies: {
        global_sort: 2,
        user_sort: 0,
        repo_sort: 0
      },
      references: {
        title: "Issues, pull requests, and discussions",
        hint: "Type # to filter",
        global_sort: 5,
        user_sort: 5,
        repo_sort: 0
      },
      organizations: {
        global_sort: 3,
      },
      teams: {
        global_sort: 6,
        user_sort: 4
      },
      users: {
        global_sort: 7,
      },
      repositories: {
        global_sort: 4,
        user_sort: 2,
        repo_sort: 0
      },
      memex_projects: {
        title: "Projects",
        global_sort: 8,
        user_sort: 3,
        repo_sort: 3
      },
      # This can be removed when the projects_classic_sunset_ui feature flag is removed
      projects: {
        title: "Projects (classic)",
        global_sort: 9,
        user_sort: 4,
        repo_sort: 4
      },
      files: {
        global_sort: 0,
        user_sort: 0,
        repo_sort: 1
      },
      footer: {
        global_sort: 99,
        user_sort: 99,
        repo_sort: 99
      },
      modes_help: {
        title: "Modes",
        global_sort: 100,
        user_sort: 100,
        repo_sort: 100
      },
      filters_help: {
        title: "Use filters in issues, pull requests, discussions, and projects",
        global_sort: 101,
        user_sort: 101,
        repo_sort: 101
      }
    }

    REGISTERED_GROUPS = GROUPS.keys

    def self.all
      GROUPS.map { |id, options| ResultGroup.new(**options.merge({ id: id })) }
    end
  end
end
