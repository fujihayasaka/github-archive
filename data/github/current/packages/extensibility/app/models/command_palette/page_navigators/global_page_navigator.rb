# typed: true
# frozen_string_literal: true

module CommandPalette
  module PageNavigators
    class GlobalPageNavigator < PageNavigator
      # Returns navigation items relevant to all users

      def items
        return [] unless scope.object.nil?

        items = []

        unless GitHub.enterprise?
          items << Result.link_to(
            priority: DEFAULT_PRIORITY + 6,
            title: "Copilot",
            icon: "copilot",
            path: copilot_immersive_path,
          )

        end

        items += [
          Result.link_to(
            priority: DEFAULT_PRIORITY + 5,
            title: "Dashboard",
            icon: "home",
            path: home_url,
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY + 4,
            title: "Notifications",
            icon: "bell",
            path: global_notifications_path
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY + 3,
            title: "Issues",
            icon: "issue-opened",
            path: all_issues_path,
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY + 2,
            title: "Pull requests",
            icon: "git-pull-request",
            path: all_pulls_path,
          ),

          Result.link_to(
            priority: DEFAULT_PRIORITY + 1,
            title: "Discussions",
            icon: "comment-discussion",
            path: all_discussions_path,
          ),
          Result.jump_to(
            current_user,
            priority: DEFAULT_PRIORITY,
            context: context
          ).tap do |result|
            result.group = "pages"
            result.typeahead = ""
            result.match_fields = ["Profile"]
          end,
          Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Settings",
            match_fields: %w[Settings Preferences],
            icon: "gear",
            path: settings_user_profile_path,
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Docs",
            icon: "info",
            path: help_url,
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Issues: assigned to you",
            icon: "issue-opened",
            path: all_issues_assigned_path,
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Issues: mentioning you",
            icon: "issue-opened",
            path: all_issues_mentioned_path,
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Pull requests: assigned to you",
            icon: "git-pull-request",
            path: all_pulls_assigned_path,
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Pull requests: mentioning you",
            icon: "git-pull-request",
            path: all_pulls_mentioned_path,
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Pull requests: requesting your review",
            icon: "git-pull-request",
            path: all_pulls_review_requested_path,
          ),
          *community_pages,
          *setting_pages
        ]

        items
      end

      private

      # General group of community-related pages, such as Explore, Topics, Marketplace, etc
      def community_pages
        pages = [
          Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Explore",
            icon: "telescope",
            path: explore_path,
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Topics",
            icon: "light-bulb",
            path: topics_path,
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Trending",
            icon: "flame",
            path: trending_index_path,
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Collections",
            icon: "stack",
            path: collections_path,
          ),
          Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Events",
            icon: "calendar",
            path: events_path,
          ),
        ]

        if GitHub.marketplace_enabled?
          pages << Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Marketplace",
            icon: "apps",
            path: marketplace_path,
          )

          pages << Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "Models",
            icon: "ai-model",
            path: marketplace_models_path,
          )
        end

        if GitHub.sponsors_enabled?
          pages << Result.link_to(
            priority: DEFAULT_PRIORITY,
            title: "GitHub Sponsors",
            icon: "heart",
            path: sponsors_path,
          )
        end

        pages
      end

      def setting_pages
        [
          settings_page("Settings > Account", "change username", "export account data", "delete account", settings_account_preferences_path),
          settings_page("Settings > Appearance", "color modes", "themes", "emoji skin tone", settings_appearance_preferences_path),
          settings_page("Settings > Accessibility", "a11y", "keyboard shortcuts", settings_accessibility_preferences_path),
          settings_page("Settings > Account security", "change password", "two-factor auth", "2fa", "sessions", settings_security_path),
          settings_page("Settings > Billing & plans", settings_user_billing_path),
          settings_page("Settings > Security log", settings_user_audit_log_path),
          settings_page("Settings > Security & analysis", settings_security_analysis_path),
          settings_page("Settings > Notifications", settings_notification_preferences_path),
          settings_page("Settings > Emails", settings_email_preferences_path),
          settings_page("Settings > SSH and GPG Keys", settings_keys_path),
          settings_page("Settings > Repositories", settings_repositories_path),
          settings_page("Settings > Packages", settings_packages_path),
          settings_page("Settings > Organizations", settings_organizations_path),
          settings_page("Settings > Enterprises", settings_enterprises_path),
          settings_page("Settings > Saved replies", saved_replies_path),
          settings_page("Settings > Applications", settings_user_installations_path),
          settings_page("Settings > Developer settings > GitHub Apps", settings_user_apps_path),
          settings_page("Settings > Developer settings > OAuth Apps", settings_user_developer_applications_path),
          settings_page("Settings > Developer settings > Personal access tokens", settings_user_tokens_path),
          settings_page("Settings > Blocked users", settings_blocked_users_path),
          settings_page("Settings > Interaction limits", settings_interaction_limits_path),
        ]
      end

      def settings_page(title, *aliases, path)
        Result.link_to(
          priority: DEFAULT_PRIORITY,
          title: title,
          icon: "gear",
          match_fields: [title] + aliases,
          path: path,
        )
      end
    end
  end
end
