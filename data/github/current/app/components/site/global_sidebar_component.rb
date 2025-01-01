# typed: true
# frozen_string_literal: true

module Site
  class GlobalSidebarComponent < ApplicationComponent
    attr_reader :nav_items, :url, :menu_items

    NavItem = Struct.new(:icon, :label, :href, keyword_init: true)
    MenuItem = Struct.new(:icon, :label, :description, :href, :divider_before, keyword_init: true)

    def initialize
      @nav_items = [
        NavItem.new(icon: :home, label: "Home", href: "/"),
        NavItem.new(icon: :inbox, label: "Inbox", href: "/notifications"),
        NavItem.new(icon: "issue-opened", label: "Issues", href: "/issues"),
        NavItem.new(icon: "git-pull-request", label: "PRs", href: "/pulls"),
        NavItem.new(icon: :copilot, label: "Copilot", href: "/copilot"),
      ]
      @menu_items = more_menu_items
    end

    private

    def more_menu_items
      [
        MenuItem.new(
          icon: :table,
          label: "Projects",
          description: "Track work across repositories and teams",
          href: "/projects"
        ),
        MenuItem.new(
          icon: :"comment-discussion",
          label: "Discussions",
          description: "Collaborate and communicate about ideas",
          href: "/discussions"
        ),
        MenuItem.new(
          icon: :codespaces,
          label: "Codespaces",
          description: "Cloud-based dev environments for your repository",
          href: "/codespaces"
        ),
        MenuItem.new(
          icon: :gift,
          label: "Marketplace",
          description: "Extend GitHub with tools and integrations",
          href: "/marketplace",
          divider_before: true
        ),
        MenuItem.new(
          icon: :telescope,
          label: "Explore",
          description: "Discover projects, topics, and trends",
          href: "/explore"
        )
      ]
    end

    def before_render
      @url = helpers.side_panels_path(panel: :global)
    end

    def render?
      logged_in? && current_user.feature_preview_enabled?(:global_nav_experiment)

    end

    def active_item?(item)
      request&.path == "/" && item.href == "/" || (request&.path&.start_with?(item.href) && item.href != "/")
    end
  end
end
