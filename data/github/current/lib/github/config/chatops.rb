# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Chatops
      extend T::Helpers
      requires_ancestor { GitHub::Config }

      # Public: The name of the MsTeams GitHub App.
      def msteams_github_app_name
        "Microsoft Teams for GitHub"
      end

      # Public: The GitHub App (Integration) that the MsTeam execution environment uses.
      def msteams_github_app
        @msteams_github_app ||= ActiveRecord::Base.connected_to(role: :reading) do
          Integration.where(
          owner_id: trusted_oauth_apps_owner,
          name: msteams_github_app_name,
        ).first
        end
      end

      # Public: The name of the Slack GitHub App.
      def slack_github_app_name
        "Slack"
      end

      # Public: The GitHub App (Integration) that the Slack execution environment uses.
      def slack_github_app
        @slack_github_app ||= ActiveRecord::Base.connected_to(role: :reading) do
          Integration.where(
          owner_id: trusted_oauth_apps_owner,
          name: slack_github_app_name,
        ).first
        end
      end

      # The name of the Slack Staging GitHub App.
      def slack_staging_github_app_name
        "Slack Staging"
      end

      # The GitHub App (Integration) that the Slack Staging execution environment uses.
      def slack_staging_github_app
        @slack_staging_github_app ||= ActiveRecord::Base.connected_to(role: :reading) do
          Apps::Privileged.integration(:slack_staging)
        end
      end

      # Public: The name of the GitHub Connector for Slack GitHub App.
      def slack_copilot_app_name
        "GitHub Connector for Slack"
      end

      # Public: The Github App (Integration) that the GitHub Connector for Slack execution environment uses.
      def slack_copilot_app
        @slack_copilot_app ||= ActiveRecord::Base.connected_to(role: :reading) do
          Integration.where(
          owner_id: trusted_oauth_apps_owner,
          name: slack_copilot_app_name,
        ).first
        end
      end

      # Public: The name of the GitHub Connector for Teams GitHub App.
      def msteams_copilot_app_name
        "GitHub Connector for Teams"
      end

      # Public: The Github App (Integration) that the GitHub Connector for Teams execution environment uses.
      def msteams_copilot_app
        @msteams_copilot_app ||= ActiveRecord::Base.connected_to(role: :reading) do
          Integration.where(
          owner_id: trusted_oauth_apps_owner,
          name: msteams_copilot_app_name,
        ).first
        end
      end
    end
  end

  extend Config::Chatops
end
