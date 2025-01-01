# typed: true
# frozen_string_literal: true

require "test_helper"

class OauthApplicationAttributeResolutionDefaultDelegateTest < GitHub::TestCase
  fixtures do
    @app = create_internal_app_with_capabilities(
      type: :oauth_application,
      capabilities: { proxima_first_party_sync: true },
      properties: { proxima_sync_delegate: :DefaultDelegate },
      options: {
        application_callback_urls: [build(:application_callback_url)],
        device_flow_enabled: true,
      },
    )
    @app.generate_client_secret(creator: @app.user)
    @manifest = ProximaAppRequest::AppManifest.new(@app.reload).serialize_manifest
  end

  test "returns the expected oauth application attribute values" do
    assert_nil @manifest[:id]
    assert_nil @manifest[:user_id]

    assert_equal @manifest[:name], @app.name
    assert_equal @manifest[:key],  @app.key

    refute_nil @manifest[:canonical_avatar_url]
    assert_equal @manifest[:canonical_avatar_url], @app.primary_avatar_url

    assert_equal @manifest[:owner][:dotcom_id],            @app.owner.id
    assert_equal @manifest[:owner][:dotcom_type],          @app.owner.type
    assert_equal @manifest[:owner][:dotcom_node_id],       @app.owner.global_relay_id
    assert_equal @manifest[:owner][:login],         @app.owner.login
    assert_equal @manifest[:owner][:display_login], @app.owner.display_login
    assert_equal @manifest[:owner][:url],           "https://github.com/#{@app.owner.display_login}"
    assert_equal @manifest[:owner][:avatar_url],    @app.owner.primary_avatar_url
  end

  test "returns expected application callback url attribute values" do
    assert_nil @manifest[:application_callback_urls].first[:created_at]

    assert_equal @manifest[:application_callback_urls].first[:url], @app.application_callback_urls.first.url
  end

  test "returns expected client secret attribute values" do
    assert_equal @manifest[:client_secrets].first[:secret_hash], @app.client_secrets.first.secret_hash
    assert_equal @manifest[:client_secrets].first[:secret_last_eight], @app.client_secrets.first.secret_last_eight
  end

  test "returns expected device control flow attribute value" do
    assert_equal @manifest[:device_flow_enabled], @app.device_flow_enabled
  end

  test "returns raw (non-interpolated) url values" do
    app = create_internal_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, properties: { proxima_sync_delegate: :DefaultDelegate }, type: :oauth_application)
    app.update!(callback_url: "https://{hostname}/callback")

    manifest = ProximaAppRequest::AppManifest.new(app.reload).serialize_manifest

    assert_equal "https://{hostname}/callback", manifest[:application_callback_urls].first[:url]
  end
end

class OauthApplicationAttributeResolutionThirdPartyDelegateTest < GitHub::TestCase
  test "expected sync policy" do
    policy = T.let(ProximaAppRequest::OauthApplicationAttributeResolutionDelegates::ThirdPartyDelegate.policy, T::Hash[Symbol, T.untyped])

    assert_equal :ineligible, policy[:oauth_application][:id]
    assert_equal :sync, policy[:oauth_application][:name]
    assert_equal :sync, policy[:oauth_application][:url]
    assert_equal :sync, policy[:oauth_application][:key]
    assert_equal :ineligible, policy[:oauth_application][:user_id]
    assert_equal :sync, policy[:oauth_application][:device_flow_enabled]
    assert_equal :sync, policy[:oauth_application][:canonical_avatar_url]

    assert_equal :ineligible, policy[:application_callback_urls][:id]
    assert_equal :sync, policy[:application_callback_urls][:url]
    assert_equal :ineligible, policy[:application_callback_urls][:application_id]
    assert_equal :ineligible, policy[:application_callback_urls][:application_type]

    assert_equal :ineligible, policy[:client_secrets][:id]
    assert_equal :ineligible, policy[:client_secrets][:oauth_application_id]
    assert_equal :ineligible, policy[:client_secrets][:creator_id]
    assert_equal :sync, policy[:client_secrets][:secret_hash]
    assert_equal :sync, policy[:client_secrets][:secret_last_eight]
    assert_equal :ineligible, policy[:client_secrets][:accessed_at]
    assert_equal :ineligible, policy[:client_secrets][:created_at]
    assert_equal :ineligible, policy[:client_secrets][:updated_at]
  end
end
