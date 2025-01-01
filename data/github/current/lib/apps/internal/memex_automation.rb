# typed: true
# frozen_string_literal: true

module Apps
  class Internal
    class MemexAutomation

      def self.id_finder
        ->() {
          Integration.find_by(
            owner_id: GitHub.trusted_apps_owner_id,
            slug: GitHub.memex_automation_github_app_slug,
          )&.id
        }
      end

      PRODUCTION = {
        alias: :memex_automation,
        id: id_finder,
        inherits: [:internal],
        capabilities: {
          user_installable: false,
          proxima_first_party_sync: true,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/memex"],
      }

      PERMISSIONS = {
        "issues" => :write,
      }

      def self.bot
        return @memex_automation_bot if defined?(@memex_automation_bot)
        @memex_automation_bot = Apps::Internal.integration(:memex_automation)&.bot
      end

      def self.reload!
        remove_instance_variable(:@memex_automation_bot) if defined?(@memex_automation_bot)
      end

      def self.seed_database!
        app = Apps::Internal.integration(:memex_automation)
        if app.present?
          puts "Memex automation app id=#{app.id} name=#{app.name} already exists, skipping..."
          return app
        end

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          name: GitHub.memex_automation_github_app_name,
          slug: GitHub.memex_automation_github_app_slug,
          url: "https://github.com/",
          public: true,
          default_permissions: PERMISSIONS,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
        }
        app = Integration.create!(integration_attributes)
        puts "Created memex automation app id=#{app.id} name=#{app.name}"

        app
      end
    end
  end
end
