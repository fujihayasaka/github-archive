# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class GitHubMetadata < Platform::Objects::Base
      description "Represents information about the GitHub instance."

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        # This is public information, anyone can see it.
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      VISIBILITY = {
        internal: { environments: [:enterprise] },
        public: { environments: [:dotcom] },
      }
      scopeless_tokens_as_minimum

      field :is_password_authentication_verifiable, Boolean, "Whether or not users are verified", method: :verifiable_password_authentication, null: false

      field :gitHubServicesSha, Scalars::GitObjectID, "Returns a String that's a SHA of `github-services`", method: :github_services_sha, null: false

      field :hook_ip_addresses, [String], method: :hooks, description: "IP addresses that service hooks are sent from", null: true, visibility: VISIBILITY

      field :git_ip_addresses, [String], method: :git, description: "IP addresses that users connect to for git operations", null: true, visibility: VISIBILITY

      field :pages_ip_addresses, [String], method: :pages, description: "IP addresses for GitHub Pages' A records", null: true, visibility: VISIBILITY

      field :importer_ip_addresses, [String], method: :importer, description: "IP addresses that the importer connects from", null: true, visibility: VISIBILITY

      field :github_enterprise_importer_ip_addresses, [String], method: :github_enterprise_importer, description: "IP addresses that GitHub Enterprise Importer uses for outbound connections", null: true, visibility: VISIBILITY

      # Enterprise-only visibility:
      field :installed_version, String, visibility: { internal: { environments: [:enterprise] } }, description: "Current installed version of GitHub Enterprise", null: false
    end
  end
end
