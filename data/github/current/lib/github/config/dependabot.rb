# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Dependabot
      def dependabot_github_app
        return nil unless GitHub.dependabot_enabled?
        return @dependabot_github_app if defined? @dependabot_github_app
        @dependabot_github_app = Integration.find_by(
          owner_id: GitHub.trusted_oauth_apps_owner,
          slug: dependabot_github_app_slug,
        )
      end

      # We occasionally check if the actor or owner is the Dependabot bot user, so let's memoize that as well
      def dependabot_github_app_bot
        return nil unless GitHub.dependabot_enabled?
        return @dependabot_github_app_bot if defined? @dependabot_github_app_bot
        @dependabot_github_app_bot = dependabot_github_app&.bot
      end

      def dependabot_github_app_name
        "Dependabot"
      end

      def dependabot_github_app_slug
        "dependabot"
      end

      def dependabot_security_updates_help_url
        "#{GitHub.help_url}/github/managing-security-vulnerabilities/configuring-dependabot-security-updates"
      end

      def dependabot_version_updates_help_url
        "#{GitHub.help_url}/github/administering-a-repository/keeping-your-dependencies-updated-automatically"
      end

      def dependabot_troubleshooting_errors_url
        "#{GitHub.help_url}/github/managing-security-vulnerabilities/troubleshooting-dependabot-errors"
      end

      def dependabot_security_and_analysis_settings_url
        "#{GitHub.help_url}/github/setting-up-and-managing-organizations-and-teams/managing-security-and-analysis-settings-for-your-organization#about-management-of-security-and-analysis-settings"
      end
    end
  end

  extend Config::Dependabot
end
