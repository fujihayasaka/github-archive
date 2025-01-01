# typed: true
# frozen_string_literal: true

require "test_helper"

class AutomaticAppInstallation::Handlers::OauthCodeExchangedTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @integration = create(:integration, default_permissions: { "metadata" => :read })
    @trigger = create(
      :integration_install_trigger,
      integration: @integration,
      install_type: :oauth_code_exchanged,
    )
  end

  test "installs the integration on targeted users" do
    handler = build_handler(
      install_triggers: [@trigger],
      originator: @integration,
      actor: @user,
    )

    refute @integration.installed_on?(@user)
    perform_enqueued_jobs(only: [InstallAutomaticIntegrationsJob]) do
      handler.install_integration
    end

    assert @integration.installed_on?(@user)
    user_installations = IntegrationInstallation.with_user(@user)
    assert_equal 1, user_installations.size
    assert user_installations.first.installed_on_all_repositories?
  end

  test "only installs on the originating app" do
    integration = create(:integration, default_permissions: { "metadata" => :read })

    create(
      :integration_install_trigger,
      integration: integration,
      install_type: :oauth_code_exchanged,
    )

    refute integration.installed_on?(@user)
    refute @integration.installed_on?(@user)

    handler = build_handler(
      install_triggers: [@trigger],
      originator: @integration,
      actor: @user,
    )

    perform_enqueued_jobs(only: [InstallAutomaticIntegrationsJob]) do
      handler.install_integration
    end

    refute integration.installed_on?(@user)
    assert @integration.installed_on?(@user)
  end

  def build_handler(install_triggers:, originator:, actor:)
    AutomaticAppInstallation::Handlers::OauthCodeExchanged.new(install_triggers:, originator:, actor:)
  end
end
