# typed: true
# frozen_string_literal: true

require "test_helper"

class AutomaticAppInstallation::Handlers::UserCreatedTest < GitHub::TestCase
  fixtures do
    @app = create(
      :integration,
      name: "Don't worry, be Appy",
      default_permissions: { "contents" => :read },
    )
    @user = create(:user)
  end

  context "UserCreated" do
    test "installs integration on configured App" do
      triggers = [
        create(:integration_install_trigger, integration: @app, install_type: :user_created),
      ]

      handler = AutomaticAppInstallation::Handlers::UserCreated.new(
        install_triggers: triggers,
        originator: @user,
        actor: @user,
      )

      Timecop.freeze do
        expected_args = [
          @user.id,
          triggers.first.integration.id,
          triggers.first.id,
          [],
          {
            "enqueued_timestamp" => Time.now.to_i,
            :entry_point => :automatic_app_installation_handler_user_created
          }
        ]

        assert_enqueued_with job: InstallAutomaticIntegrationsJob, args: expected_args do
          handler.install_integration
        end
      end
    end
  end
end
