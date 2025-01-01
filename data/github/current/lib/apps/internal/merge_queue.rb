# typed: true
# frozen_string_literal: true

module Apps
  class Internal
    class MergeQueue
      def self.id_finder
        ->() {
          Integration.find_by(
            owner_id: GitHub.trusted_apps_owner_id,
            slug: GitHub.merge_queue_github_app_slug,
          )&.id
        }
      end

      PRODUCTION = {
        alias: :merge_queue,
        id: id_finder,
        inherits: [:internal],
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

      def self.id
        return @merge_queue_id if defined?(@merge_queue_id)
        @merge_queue_id = Apps::Internal.integration_id(:merge_queue)
      end

      def self.seed_database!
        return if Apps::Internal.integration(:merge_queue).present?

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          name: GitHub.merge_queue_github_app_name,
          slug: GitHub.merge_queue_github_app_slug,
          url: "https://github.com/",
          public: true,
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
