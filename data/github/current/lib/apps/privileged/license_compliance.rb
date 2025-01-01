# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class LicenseCompliance

      APP_NAME = "GitHub License Compliance"

      PRODUCTION = {
        alias: :license_compliance,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: APP_NAME },
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
        owners: ["@github/dependency-graph"],
      }

      def self.seed_database!
        app = Apps::Privileged.integration(:license_compliance)
        if app.present?
          puts "License Compliance app id=#{app.id} name=#{app.name} already exists, skipping..."
          return app
        end

        integration_attributes = {
          owner: GitHub.first_party_apps_owner,
          name: APP_NAME,
          url: "https://github.com/",
          visibility: :public_visibility,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
        }
        app = Integration.create!(integration_attributes)
        puts "Created license_compliance app id=#{app.id} name=#{app.name}"

        app
      end
    end
  end
end
