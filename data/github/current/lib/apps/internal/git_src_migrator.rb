# typed: true
# frozen_string_literal: true

module Apps
  class Internal
    class GitSrcMigrator
      def self.id_finder
        ->() {
          Integration.find_by(
            owner_id: GitHub.trusted_apps_owner_id,
            slug: GitHub.git_src_migrator_github_app_slug,
          )&.id
        }
      end

      PRODUCTION = {
        alias: :git_src_migrator,
        id: id_finder,
        inherits: [:internal],
        capabilities: {
          installed_globally: false,
          limited_access: false,
          enforce_internal_access_on_token_generation: false,
          user_installable: false,
          actions_dynamic_workflows: true
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/migration-tools"],
      }
    end
  end
end
