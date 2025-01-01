# typed: true
# frozen_string_literal: true

require "test_helper"

class AutomaticAppInstallation::Handlers::ButtonClickedTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, :minimal)
    @integration = create(:integration, default_permissions: { "metadata" => :read })
    @trigger = create(:integration_install_trigger, integration: @integration, install_type: :button_clicked)
  end

  context "#install_integration" do
    test "synchronously installs the integration on the targeted user" do
      handler = build_handler(
        install_triggers: [@trigger],
        originator: @integration,
        actor: @repo,
      )

      handler.install_integration

      assert @integration.installed_on?(@repo.owner)
      user_installations = IntegrationInstallation.with_user(@repo.owner)
      assert_equal 1, user_installations.size
      refute user_installations.first.installed_on_all_repositories?
    end

    test "does not install if the integration doesn't have an associated trigger" do
      integration = create(:integration, default_permissions: { "metadata" => :read })

      handler = build_handler(
        install_triggers: [@trigger],
        originator: integration,
        actor: @repo,
      )

      handler.install_integration
      refute integration.installed_on?(@repo.owner)
    end
  end

  def build_handler(install_triggers:, originator:, actor:)
    AutomaticAppInstallation::Handlers::ButtonClicked.new(
      install_triggers: install_triggers,
      originator: originator,
      actor: actor,
    )
  end
end
