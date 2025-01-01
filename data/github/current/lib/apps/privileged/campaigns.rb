# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class Campaigns

      APP_NAME = "GitHub Campaigns"

      def self.id_finder
        ->() {
          Integration.find_by(
            owner_id: GitHub.first_party_apps_owner_id,
            name: APP_NAME,
          )&.id
        }
      end

      PRODUCTION = {
        alias: :campaigns,
        id: id_finder,
        inherits: [],
        capabilities: {
          attribution_only_system_identity: true, # Can _only_ be used for actor attribution. Cannot call the public api.github.com APIs.
          proxima_first_party_sync: true,
          user_installable: false,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/code-scanning-experiences"],
      }

      def self.seed_database!
        app = Apps::Privileged.integration(:campaigns)
        if app.present?
          puts "Campaigns app id=#{app.id} name=#{app.name} already exists, skipping..."
          return app
        end

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          name: APP_NAME,
          url: "https://github.com/",
          visibility: :public_visibility,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
        }
        app = Integration.create!(integration_attributes)
        puts "Created campaigns app id=#{app.id} name=#{app.name}"

        app
      end
    end
  end
end
