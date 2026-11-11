# typed: true
# frozen_string_literal: true

module CommandPalette
  class HelpItems

    ITEMS = [
      HelpItem.new(
        title: GitHub::HTMLSafeString.make("Search for <strong>issues</strong> and <strong>pull requests</strong>"),
        prefix: "#",
        group: :modes_help,
        scope_types: [:global]
      ),
      HelpItem.new(
        title: GitHub::HTMLSafeString.make("Search for <strong>issues, pull requests, discussions,</strong> and <strong>projects</strong>"),
        prefix: "#",
        group: :modes_help,
        scope_types: [:owner, :repository]
      ),
      HelpItem.new(
        title: GitHub::HTMLSafeString.make("Search for <strong>organizations, repositories,</strong> and <strong>users</strong>"),
        prefix: "@",
        group: :modes_help,
        scope_types: [:global]
      ),
      HelpItem.new(
        title: GitHub::HTMLSafeString.make("Search for <strong>projects</strong>"),
        prefix: "!",
        group: :modes_help,
        scope_types: [:owner, :repository]
      ),
      HelpItem.new(
        title: GitHub::HTMLSafeString.make("Search for <strong>files</strong>"),
        prefix: "/",
        group: :modes_help,
        scope_types: [:repository]
      ),
      HelpItem.new(
        title: GitHub::HTMLSafeString.make("Activate <strong>command mode</strong>"),
        prefix: ">",
        group: :modes_help,
        scope_types: []
      ),
      HelpItem.new(
        title: "Search your issues, pull requests, and discussions",
        prefix: "# author:@me",
        group: :filters_help,
        scope_types: []
      ),
      HelpItem.new(
        title: "Search your issues, pull requests, and discussions",
        prefix: "# author:@me",
        group: :filters_help,
        scope_types: []
      ),
      HelpItem.new(
        title: "Filter to pull requests",
        prefix: "# is:pr",
        group: :filters_help,
        scope_types: []
      ),
      HelpItem.new(
        title: "Filter to issues",
        prefix: "# is:issue",
        group: :filters_help,
        scope_types: []
      ),
      HelpItem.new(
        title: "Filter to discussions",
        prefix: "# is:discussion",
        group: :filters_help,
        scope_types: [:owner, :repository]
      ),
      HelpItem.new(
        title: "Filter to projects",
        prefix: "# is:project",
        group: :filters_help,
        scope_types: [:owner, :repository]
      ),
      HelpItem.new(
        title: "Filter to open issues, pull requests, and discussions",
        prefix: "# is:open",
        group: :filters_help,
        scope_types: []
      )
    ]

    def self.all
      ITEMS
    end
  end
end
