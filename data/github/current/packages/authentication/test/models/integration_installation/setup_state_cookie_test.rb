# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationInstallationSetupStateCookieTest < GitHub::TestCase
  fixtures do
    @integration = create(:integration)
    @state = "12345"
    @data = { "state" => @state }
  end

  setup do
    @cookie_jar = ActionDispatch::Request.new(Rails.application.env_config.deep_dup).cookie_jar
    @cookie_jar.clear
  end

  test ".create sets a cookie if data is present" do
    assert_nil @cookie_jar[IntegrationInstallation::SetupStateCookie::COOKIE_NAME]

    IntegrationInstallation::SetupStateCookie.create(
      cookie_jar: @cookie_jar,
      data: @data,
      integration_id: @integration.global_relay_id,
      target_id: 42,
    )

    refute_nil @cookie_jar[IntegrationInstallation::SetupStateCookie::COOKIE_NAME]
  end

  test ".delete removes cookie" do
    IntegrationInstallation::SetupStateCookie.create(
      cookie_jar: @cookie_jar,
      data: @data,
      integration_id: @integration.global_relay_id,
      target_id: 42,
    )
    refute_nil @cookie_jar[IntegrationInstallation::SetupStateCookie::COOKIE_NAME]

    IntegrationInstallation::SetupStateCookie.delete(cookie_jar: @cookie_jar)

    assert_nil @cookie_jar[IntegrationInstallation::SetupStateCookie::COOKIE_NAME]
  end

  context "#save" do
    test "persists the cookie if there's any data" do
      assert_nil @cookie_jar[IntegrationInstallation::SetupStateCookie::COOKIE_NAME]
      cookie = IntegrationInstallation::SetupStateCookie.new(
        cookie_jar: @cookie_jar,
        data: @data,
        integration_id: @integration.global_relay_id,
        target_id: 42,
      )
      cookie.save
      refute_nil @cookie_jar[IntegrationInstallation::SetupStateCookie::COOKIE_NAME]
    end

    test "doesn't persist the cookie if there's no data" do
      assert_nil @cookie_jar[IntegrationInstallation::SetupStateCookie::COOKIE_NAME]

      cookie = IntegrationInstallation::SetupStateCookie.new(
        cookie_jar: @cookie_jar,
        data: {},
        integration_id: @integration.global_relay_id,
        target_id: 42,
      )
      cookie.save
      assert_nil @cookie_jar[IntegrationInstallation::SetupStateCookie::COOKIE_NAME]
    end
  end

  test "loads values from cookie" do
    @cookie_jar.delete(IntegrationInstallation::SetupStateCookie::COOKIE_NAME)
    assert_nil @cookie_jar.signed[IntegrationInstallation::SetupStateCookie::COOKIE_NAME]

    @cookie_jar.signed[IntegrationInstallation::SetupStateCookie::COOKIE_NAME] = JSON.generate({
      data: @data,
      integration_id: @integration.global_relay_id,
      target_id: 43,
    })

    setup_state = IntegrationInstallation::SetupStateCookie.new(cookie_jar: @cookie_jar)

    assert_equal @data, setup_state.data
    assert_equal @integration.global_relay_id, setup_state.integration_id
    assert_equal 43, setup_state.target_id
  end

  test "#state_param" do
    setup_state = IntegrationInstallation::SetupStateCookie.create(
      cookie_jar: @cookie_jar,
      data: @data,
      integration_id: @integration.global_relay_id,
      target_id: 42,
    )

    assert_nil setup_state.state_param(integration_id: "#{@integration.global_relay_id}42", target_id: 42)
    assert_nil setup_state.state_param(integration_id: @integration.global_relay_id, target_id: 17)
    assert_equal @state, setup_state.state_param(integration_id: @integration.global_relay_id, target_id: 42)
  end

  test "#state_param with no target_id" do
    setup_state = IntegrationInstallation::SetupStateCookie.create(
      cookie_jar: @cookie_jar,
      data: @data,
      integration_id: @integration.global_relay_id,
      target_id: nil,
    )

    assert_nil setup_state.state_param(integration_id: "#{@integration.global_relay_id}42", target_id: 42)

    assert_equal @state, setup_state.state_param(integration_id: @integration.global_relay_id, target_id: 17)
    assert_equal @state, setup_state.state_param(integration_id: @integration.global_relay_id, target_id: nil)
  end

end
