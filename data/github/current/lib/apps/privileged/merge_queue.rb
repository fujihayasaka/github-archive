# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class MergeQueue
      PRODUCTION = {
        alias: :merge_queue,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, slug: GitHub.merge_queue_github_app_slug },
        inherits: [:first_party],
        capabilities: {
          user_installable: false,
          proxima_first_party_sync: true,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/pull-requests"],
      }

      PERMISSIONS = {}

      def self.seed_database!
        return if Apps::Privileged.integration(:merge_queue).present?

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          name: GitHub.merge_queue_github_app_name,
          slug: GitHub.merge_queue_github_app_slug,
          url: "https://github.com/",
          visibility: :public_visibility,
          default_permissions: PERMISSIONS,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
        }
        app = Integration.create!(integration_attributes)

        app
      end
    end
  end
end
