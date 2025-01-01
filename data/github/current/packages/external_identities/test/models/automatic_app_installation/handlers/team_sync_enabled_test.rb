# typed: true
# frozen_string_literal: true

require "test_helper"

class AutomaticAppInstallation::Handlers::TeamSyncEnabledTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @app = create(
      :integration,
      name: "Don't worry, be Appy",
      default_permissions: { "contents" => :read },
    )
    @user = create(:user)
    @org = create(:organization)
    @trigger = create(:integration_install_trigger, integration: @app, install_type: :team_sync_enabled)
    triggers = [@trigger]
    @handler = AutomaticAppInstallation::Handlers::TeamSyncEnabled.new(
      install_triggers: triggers,
      originator: @org,
      actor: @user,
    )
  end

  context "TeamSyncEnabled" do
    test "installs integration on configured App when feature is enabled" do
      Timecop.freeze do
        expected_args = [
          @org.id,
          @trigger.integration.id,
          @trigger.id,
          [],
          {
            "enqueued_timestamp" => Time.now.to_i,
            :entry_point => :automatic_app_installation_handler_team_sync_enabled
          }
        ]

        assert_enqueued_with job: InstallAutomaticIntegrationsJob, args: expected_args do
          @handler.install_integration
        end
      end
    end
  end
end
