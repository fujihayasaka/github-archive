# typed: true
# frozen_string_literal: true

require "test_helper"

class ProximaAppRequest
  module IntegrationAttributeResolutionDelegates
    module ACustomTestDelegate
    end
  end
end

class AttributeResolutionTest < GitHub::TestCase
  setup do
    Apps::Privileged::Registry.reset_configuration!
  end

  test "delegates to DefaultDelegate for first-party integration with proxima_first_party_sync capability" do
    internal_app = create_privileged_app_with_capabilities(properties: { proxima_sync_delegate: :DefaultDelegate }, capabilities: { proxima_first_party_sync: true })

    actual_delegate = ProximaAppRequest::AttributeResolution.delegate(app: internal_app)
    expected_delegate = ProximaAppRequest::IntegrationAttributeResolutionDelegates::DefaultDelegate

    assert_equal expected_delegate, actual_delegate
  end

  test "delegates to DefaultDelegate for first-party OAuth App with proxima_first_party_sync capability" do
    oauth_app = create_privileged_app_with_capabilities(properties: { proxima_sync_delegate: :DefaultDelegate }, capabilities: { proxima_first_party_sync: true }, type: :oauth_application)

    actual_delegate = ProximaAppRequest::AttributeResolution.delegate(app: oauth_app)
    expected_delegate = ProximaAppRequest::OauthApplicationAttributeResolutionDelegates::DefaultDelegate

    assert_equal expected_delegate, actual_delegate
  end

  test "delegates to ACustomTestDelegate for first-party app with proxima_first_party_sync" do
    internal_app = create_privileged_app_with_capabilities(properties: { proxima_sync_delegate: :ACustomTestDelegate }, capabilities: { proxima_first_party_sync: true })
    actual_delegate = ProximaAppRequest::AttributeResolution.delegate(app: internal_app)
    expected_delegate = ProximaAppRequest::IntegrationAttributeResolutionDelegates::ACustomTestDelegate

    assert_equal expected_delegate, actual_delegate
  end

  test "delegates to ThirdPartyDelegate for third-party integration with proxima sync enabled" do
    integration = create(:integration, proxima_availability: :available)
    actual_delegate = ProximaAppRequest::AttributeResolution.delegate(app: integration)
    expected_delegate = ProximaAppRequest::IntegrationAttributeResolutionDelegates::ThirdPartyDelegate

    assert_equal expected_delegate, actual_delegate
  end

  test "delegates to ThirdPartyDelegate for third-party OAuth App with proxima sync enabled" do
    app = create(:oauth_application, proxima_availability: :available)
    actual_delegate = ProximaAppRequest::AttributeResolution.delegate(app: app)
    expected_delegate = ProximaAppRequest::OauthApplicationAttributeResolutionDelegates::ThirdPartyDelegate

    assert_equal expected_delegate, actual_delegate
  end
end
