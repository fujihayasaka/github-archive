# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module IssueFieldsProjectsSync
      # rubocop:disable Style/WordArray
      CONFIG = {
        repositories: [
          # "github/issue-fields",
          "github/planning-tracking-demo",
          "github/issues",
          "github/memex",
          "github/mysql-database-usage",
          "github/github",
          "github/copilot-indexing-issues-prs",
          "github/copilot-issues-xp",
          "github/issue-dependencies",
          "github/projects-platform",
          "github/repos",
          "github/notifications",
          "github/slack",
          "github/notifyd",
          "github/copilot",
          "github/copilot-api",
          "github/epd-operations",
        ],
        projects: [
          "github/22374", # Text memex/issue fields sync
          "github/5842", # Issues Backlog
          "github/21633", # Issue Fields
          "github/4017", # Projects Shared FR Triage
          "github/22172", # Copilot Indexing for Issues and PRs
          "github/22740", # Copilot Issues XP
          "github/19511", # Issue Dependencies
          "github/22403", # Issue fields in Projects
          "github/11065", # Issues Tiny Wins
          "github/9422", # Repos Health
          "github/9466", # Repos Application
          "github/5705", # Repos First Responder
          "github/5895", # Repos Platform
          "github/5812", # Notifications FR
          "github/19648", # Notifications Integrations - Workstreams
          "github/10303", # Notifications Platform - Workstreams
          "github/13488", # Copilot API
          "github/13784", # Operational Excellence
          "Plan-Track-Playground/8", # Plan-Track-Playground - Octo Games
          "github/20800", # @labudis personal project
        ],
        fields: [
          "Priority",
          "Source",
          "Visibility",
          "Impact",
          "Effort",
          "DRI",
          "Start Date",
          "Target Date",
          "Trending",
          "Engineering Staffing",
        ]
      }.freeze
      # rubocop:enable Style/WordArray

      sig { params(project: String).returns(T::Boolean) }
      def self.enabled_for_project?(project)
        CONFIG[:projects].include?(project)
      end

      sig { params(repository: Repository).returns(T::Boolean) }
      def self.enabled_for_repository?(repository)
        (CONFIG[:repositories].include?(repository.name_with_display_owner) && FeatureFlag.vexi.enabled?(:issue_fields_sync_with_projects, repository, default: false)) || false
      end

      def self.enabled_for_field?(field)
        CONFIG[:fields].include?(field)
      end
    end
  end

  extend Config::IssueFieldsProjectsSync
end
