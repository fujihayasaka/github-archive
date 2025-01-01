# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class InternalIntegrations < Seeds::Runner
      def self.help
        <<~EOF
        Create Internal GitHub-Owned Integrations.
        Creates Slack, Teams and chatops-unfurl (used by Slack).

        Override their URLs by using the SLACK_INTEGRATION_URL and TEAMS_INTEGRATION_URL env var.

        -f    Force deletion and recreation of the integrations.
        -p    Print the app info for the integrations when they're created.
        -m    Create integrations for multi-tenant mode.
        EOF
      end

      def self.run(options = {})
        print_app_info = options[:print_app_info]
        force = options[:force]
        output_file = options[:output_file]
        slack_integration_url = options[:slack_integration_url]
        teams_integration_url = options[:teams_integration_url]
        multi_tenant = options[:multi_tenant]

        puts "➡️ Creating Slack integration..."
        Seeds::Objects::Integration.create_slack_integration(force: force, print_app_info: print_app_info,
          output_file: output_file, integration_url: slack_integration_url, mt: multi_tenant)

        puts "➡️ Creating Teams integration..."
        Seeds::Objects::Integration.create_msteams_integration(force: force, print_app_info: print_app_info,
          output_file: output_file, integration_url: teams_integration_url, mt: multi_tenant)

        unless GitHub.enterprise?
          puts "➡️ Creating chatops unfurl integration..."
          Seeds::Objects::Integration.create_chatops_unfurl_integration(force: force, print_app_info: print_app_info,
            output_file: output_file, integration_url: slack_integration_url, mt: multi_tenant)
        end

        if output_file.present?
          puts "➡️ Wrote app info to #{output_file}"
        end

        # After creating privileged (nee. internal) apps, it's necessary to
        # reload the in-memory caches for the privileged apps registry. This
        # ensures newly created apps can be found by alias and that capability
        # checks work as expected.
        Apps::Privileged::Registry.instance.reload_caches!
      end
    end
  end
end
