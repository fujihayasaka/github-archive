# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class GitSrcMigrator
      PRODUCTION = {
        alias: :git_src_migrator,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, slug: GitHub.git_src_migrator_github_app_slug },
        inherits: [:first_party],
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
