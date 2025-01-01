# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationAttributeResolutionDefaultDelegateTest < GitHub::TestCase
  fixtures do
    @integration = create_privileged_app_with_capabilities(
      capabilities: { proxima_first_party_sync: true },
       properties: { proxima_sync_delegate: :DefaultDelegate },
       options: {
        name: "Example Integration",
        url: "https://example.com",
        description: "Example Integration Description",
        visibility: "public_visibility",
        slug: "example-integration",
        setup_url: "https://example.com/setup",
        bgcolor: "#000000",
        setup_on_update: true,
        request_oauth_on_install: true,
        user_token_expiration: 1,
        state: "active",
        device_flow_enabled: true,
        note: "Example Note",
        default_permissions: { "metadata" => :read, "single_file" => :read },
        default_events: ["label"],
        single_file_name: "example.txt",
        application_callback_urls: [build(:application_callback_url, url: "https://example.com/callback")],
        hook: build(:hook, active: true, confirmed: true, pinned_api_version: GitHub.api_versions.last, secret: "Example Secret"),
        integration_install_triggers: [build(:integration_install_trigger, path: "https://example.com", reason: "Example Reason")],
        ip_allowlist_entries: [build(:ip_allowlist_entry, name: "Example IP Allowlist Entry")],
        public_keys: [build(:integration_key, public_pem: OpenSSL::PKey::RSA.new(2048).public_key.to_pem)],
       }
      )
    @integration.generate_client_secret(creator: @integration.owner)
  end

  def setup
    @manifest = ProximaAppRequest::AppManifest.new(@integration.reload).serialize_manifest
  end

  test "returns the expected integration attribute values" do
    assert_nil @manifest[:bot_id]

    assert_equal @manifest[:name], @integration.name
    assert_equal @manifest[:url], @integration.url
    assert_equal @manifest[:description], @integration.description
    assert_equal @manifest[:visibility], @integration.visibility
    assert_equal @manifest[:slug], @integration.slug
    assert_equal @manifest[:key], @integration.key
    assert_equal @manifest[:setup_url], @integration.setup_url
    assert_equal @manifest[:bgcolor], @integration.bgcolor
    assert_equal @manifest[:setup_on_update], @integration.setup_on_update
    assert_equal @manifest[:request_oauth_on_install], @integration.request_oauth_on_install
    assert_equal @manifest[:user_token_expiration], @integration.user_token_expiration
    assert_equal @manifest[:state], @integration.state_before_type_cast
    assert_equal @manifest[:device_flow_enabled], @integration.device_flow_enabled
  end

  test "returns expected application callback url attribute values" do
    assert_nil @manifest[:application_callback_urls].first[:id]

    assert_equal @manifest[:application_callback_urls].first[:url], @integration.application_callback_urls.first.url
  end

  test "returns expected hook attribute values" do
    assert_nil @manifest[:hook][:events]

    assert_equal @manifest[:hook][:name], @integration.hook.name
    assert_equal @manifest[:hook][:active], @integration.hook.active
    assert_equal @manifest[:hook][:confirmed], @integration.hook.confirmed
    assert_equal @manifest[:hook][:pinned_api_version], @integration.hook.pinned_api_version
    assert_equal @manifest[:hook][:content_type], @integration.hook.content_type
    assert_equal @manifest[:hook][:insecure_ssl], @integration.hook.insecure_ssl
    assert_equal @manifest[:hook][:url], @integration.hook.url
    assert_equal @manifest[:hook][:secret], @integration.hook.secret
  end

  test "returns expected latest_version attribute values" do
    assert_equal @manifest[:latest_version][:default_permissions], @integration.default_permissions
    assert_equal @manifest[:latest_version][:default_events], @integration.default_events
    assert_equal @manifest[:latest_version][:single_file_name], @integration.single_file_name
    assert_equal @manifest[:latest_version][:note], @integration.latest_version.note
  end

  test "returns expected integration install trigger attribute values" do
    assert_equal @manifest[:integration_install_triggers].first[:path], @integration.integration_install_triggers.first.path
    assert_equal @manifest[:integration_install_triggers].first[:reason], @integration.integration_install_triggers.first.reason
    assert_equal @manifest[:integration_install_triggers].first[:deactivated], @integration.integration_install_triggers.first.deactivated
    assert_equal @manifest[:integration_install_triggers].first[:install_type], @integration.integration_install_triggers.first.install_type
  end

  test "returns expected ip allowlist entry attribute values" do
    assert_equal @manifest[:ip_allowlist_entries].first[:allow_list_value], @integration.ip_allowlist_entries.first.allow_list_value
    assert_equal @manifest[:ip_allowlist_entries].first[:range_from], @integration.ip_allowlist_entries.first.range_from
    assert_equal @manifest[:ip_allowlist_entries].first[:range_to], @integration.ip_allowlist_entries.first.range_to
    assert_equal @manifest[:ip_allowlist_entries].first[:name], @integration.ip_allowlist_entries.first.name
    assert_equal @manifest[:ip_allowlist_entries].first[:active], @integration.ip_allowlist_entries.first.active
  end

  test "returns expected client secrets attribute values" do
    assert_equal @manifest[:client_secrets].first[:secret_hash], @integration.client_secrets.first.secret_hash
    assert_equal @manifest[:client_secrets].first[:secret_last_eight], @integration.client_secrets.first.secret_last_eight
  end

  test "returns raw (non-interpolated) url values" do
    integration = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, properties: { proxima_sync_delegate: :DefaultDelegate })
    hook = create :hook, installation_target: integration
    integration.update!(setup_url: "https://{hostname}/setup")
    integration.application_callback_urls.create!(url: "https://{hostname}/callback")
    hook.update!(url: "https://{hostname}/callback")

    manifest = ProximaAppRequest::AppManifest.new(integration.reload).serialize_manifest

    assert_equal "https://{hostname}/setup", manifest[:setup_url]
    assert_equal "https://{hostname}/callback", manifest[:hook][:url]
    assert_equal "https://{hostname}/callback", manifest[:application_callback_urls].first[:url]
  end

  test "returns the expected canonical_avatar_url attribute value" do
    refute_nil @manifest[:canonical_avatar_url]
    assert_equal @manifest[:canonical_avatar_url], @integration.primary_avatar_url
  end

  test "returns the expected owner attributes" do
    assert_equal @manifest[:owner][:dotcom_id], @integration.owner.id
    assert_equal @manifest[:owner][:dotcom_type], @integration.owner.type
    assert_equal @manifest[:owner][:dotcom_node_id], @integration.owner.global_relay_id
    assert_equal @manifest[:owner][:login], @integration.owner.login
    assert_equal @manifest[:owner][:display_login], @integration.owner.display_login
    assert_equal @manifest[:owner][:url], "https://github.com/#{@integration.owner.display_login}"
    assert_equal @manifest[:owner][:avatar_url], @integration.owner.primary_avatar_url
  end

  test "returns expected public_key attributes" do
    assert_equal @manifest[:public_keys].size, 1
    assert_equal @manifest[:public_keys].first, { public_pem: nil }
  end

  test "expected sync policy" do
    policy = T.let(ProximaAppRequest::IntegrationAttributeResolutionDelegates::DefaultDelegate.policy, T::Hash[Symbol, T.untyped])

    assert_equal :ineligible, policy[:integration][:id]
    assert_equal :ineligible, policy[:integration][:bot_id]
    assert_equal :sync, policy[:integration][:name]
    assert_equal :sync, policy[:integration][:url]
    assert_equal :sync, policy[:integration][:description]
    assert_equal :sync, policy[:integration][:visibility]
    assert_equal :sync, policy[:integration][:slug]
    assert_equal :sync, policy[:integration][:key]
    assert_equal :sync, policy[:integration][:setup_url]
    assert_equal :sync, policy[:integration][:bgcolor]
    assert_equal :sync, policy[:integration][:setup_on_update]
    assert_equal :sync, policy[:integration][:deleted_at]
    assert_equal :sync, policy[:integration][:request_oauth_on_install]
    assert_equal :sync, policy[:integration][:user_token_expiration]
    assert_equal :sync, policy[:integration][:state]
    assert_equal :sync, policy[:integration][:suspended_at]
    assert_equal :ineligible, policy[:integration][:user_suspended_by_id]
    assert_equal :sync, policy[:integration][:pinned_api_version]
    assert_equal :sync, policy[:integration][:device_flow_enabled]
    assert_equal :sync, policy[:integration][:default_permissions]
    assert_equal :sync, policy[:integration][:canonical_avatar_url]

    assert_equal :ineligible, policy[:latest_version][:id]
    assert_equal :sync, policy[:latest_version][:note]
    assert_equal :sync, policy[:latest_version][:default_permissions]
    assert_equal :sync, policy[:latest_version][:default_events]
    assert_equal :sync, policy[:latest_version][:single_file_name]

    assert_equal :ineligible, policy[:application_callback_urls][:id]
    assert_equal :sync, policy[:application_callback_urls][:url]
    assert_equal :ineligible, policy[:application_callback_urls][:application_id]
    assert_equal :ineligible, policy[:application_callback_urls][:application_type]

    assert_equal :ineligible, policy[:hook][:id]
    assert_equal :sync, policy[:hook][:name]
    assert_equal :sync, policy[:hook][:active]
    assert_equal :sync, policy[:hook][:confirmed]
    assert_equal :ineligible, policy[:hook][:installation_target_type]
    assert_equal :ineligible, policy[:hook][:installation_target_id]
    assert_equal :ineligible, policy[:hook][:oauth_application_id]
    assert_equal :sync, policy[:hook][:pinned_api_version]
    assert_equal :sync, policy[:hook][:url]
    assert_equal :sync, policy[:hook][:secret]
    assert_equal :sync, policy[:hook][:content_type]
    assert_equal :sync, policy[:hook][:insecure_ssl]

    assert_equal :ineligible, policy[:integration_install_triggers][:id]
    assert_equal :ineligible, policy[:integration_install_triggers][:integration_id]
    assert_equal :sync, policy[:integration_install_triggers][:install_type]
    assert_equal :sync, policy[:integration_install_triggers][:path]
    assert_equal :sync, policy[:integration_install_triggers][:reason]
    assert_equal :sync, policy[:integration_install_triggers][:deactivated]

    assert_equal :ineligible, policy[:ip_allowlist_entries][:id]
    assert_equal :sync, policy[:ip_allowlist_entries][:allow_list_value]
    assert_equal :sync, policy[:ip_allowlist_entries][:range_from]
    assert_equal :sync, policy[:ip_allowlist_entries][:range_to]
    assert_equal :sync, policy[:ip_allowlist_entries][:name]
    assert_equal :sync, policy[:ip_allowlist_entries][:active]

    assert_equal :ineligible, policy[:client_secrets][:id]
    assert_equal :ineligible, policy[:client_secrets][:oauth_application_id]
    assert_equal :ineligible, policy[:client_secrets][:creator_id]
    assert_equal :sync, policy[:client_secrets][:secret_hash]
    assert_equal :sync, policy[:client_secrets][:secret_last_eight]
    assert_equal :ineligible, policy[:client_secrets][:accessed_at]
    assert_equal :ineligible, policy[:client_secrets][:created_at]
    assert_equal :ineligible, policy[:client_secrets][:updated_at]

    assert_equal :ineligible, policy[:public_keys][:id]
    assert_equal :ineligible, policy[:public_keys][:integration_id]
    assert_equal :ineligible, policy[:public_keys][:creator_id]
    assert_equal :ineligible, policy[:public_keys][:public_pem]
    assert_equal :ineligible, policy[:public_keys][:created_at]
    assert_equal :ineligible, policy[:public_keys][:updated_at]
  end
end

class IntegrationAttributeResolutionThirdPartyDelegateTest < GitHub::TestCase
  test "expected sync policy" do
    policy = T.let(ProximaAppRequest::IntegrationAttributeResolutionDelegates::ThirdPartyDelegate.policy, T::Hash[Symbol, T.untyped])

    assert_equal :ineligible, policy[:integration][:id]
    assert_equal :ineligible, policy[:integration][:bot_id]
    assert_equal :sync, policy[:integration][:name]
    assert_equal :sync, policy[:integration][:url]
    assert_equal :sync, policy[:integration][:description]
    assert_equal :sync, policy[:integration][:visibility]
    assert_equal :sync, policy[:integration][:slug]
    assert_equal :sync, policy[:integration][:key]
    assert_equal :sync, policy[:integration][:setup_url]
    assert_equal :sync, policy[:integration][:bgcolor]
    assert_equal :sync, policy[:integration][:setup_on_update]
    assert_equal :sync, policy[:integration][:deleted_at]
    assert_equal :sync, policy[:integration][:request_oauth_on_install]
    assert_equal :sync, policy[:integration][:user_token_expiration]
    assert_equal :sync, policy[:integration][:state]
    assert_equal :sync, policy[:integration][:suspended_at]
    assert_equal :ineligible, policy[:integration][:user_suspended_by_id]
    assert_equal :sync, policy[:integration][:pinned_api_version]
    assert_equal :sync, policy[:integration][:device_flow_enabled]
    assert_equal :sync, policy[:integration][:default_permissions]
    assert_equal :sync, policy[:integration][:canonical_avatar_url]

    assert_equal :ineligible, policy[:latest_version][:id]
    assert_equal :sync, policy[:latest_version][:note]
    assert_equal :sync, policy[:latest_version][:default_permissions]
    assert_equal :sync, policy[:latest_version][:default_events]
    assert_equal :sync, policy[:latest_version][:single_file_name]

    assert_equal :ineligible, policy[:application_callback_urls][:id]
    assert_equal :sync, policy[:application_callback_urls][:url]
    assert_equal :ineligible, policy[:application_callback_urls][:application_id]
    assert_equal :ineligible, policy[:application_callback_urls][:application_type]

    assert_equal :ineligible, policy[:hook][:id]
    assert_equal :sync, policy[:hook][:name]
    assert_equal :sync, policy[:hook][:active]
    assert_equal :sync, policy[:hook][:confirmed]
    assert_equal :ineligible, policy[:hook][:installation_target_type]
    assert_equal :ineligible, policy[:hook][:installation_target_id]
    assert_equal :ineligible, policy[:hook][:oauth_application_id]
    assert_equal :sync, policy[:hook][:pinned_api_version]
    assert_equal :sync, policy[:hook][:url]
    assert_equal :sync, policy[:hook][:secret]
    assert_equal :sync, policy[:hook][:content_type]
    assert_equal :sync, policy[:hook][:insecure_ssl]

    assert_equal :ineligible, policy[:integration_install_triggers][:id]
    assert_equal :ineligible, policy[:integration_install_triggers][:integration_id]
    assert_equal :sync, policy[:integration_install_triggers][:install_type]
    assert_equal :sync, policy[:integration_install_triggers][:path]
    assert_equal :sync, policy[:integration_install_triggers][:reason]
    assert_equal :sync, policy[:integration_install_triggers][:deactivated]

    assert_equal :ineligible, policy[:ip_allowlist_entries][:id]
    assert_equal :sync, policy[:ip_allowlist_entries][:allow_list_value]
    assert_equal :sync, policy[:ip_allowlist_entries][:range_from]
    assert_equal :sync, policy[:ip_allowlist_entries][:range_to]
    assert_equal :sync, policy[:ip_allowlist_entries][:name]
    assert_equal :sync, policy[:ip_allowlist_entries][:active]

    assert_equal :ineligible, policy[:client_secrets][:id]
    assert_equal :ineligible, policy[:client_secrets][:oauth_application_id]
    assert_equal :ineligible, policy[:client_secrets][:creator_id]
    assert_equal :sync, policy[:client_secrets][:secret_hash]
    assert_equal :sync, policy[:client_secrets][:secret_last_eight]
    assert_equal :ineligible, policy[:client_secrets][:accessed_at]
    assert_equal :ineligible, policy[:client_secrets][:created_at]
    assert_equal :ineligible, policy[:client_secrets][:updated_at]

    assert_equal :ineligible, policy[:public_keys][:id]
    assert_equal :ineligible, policy[:public_keys][:integration_id]
    assert_equal :ineligible, policy[:public_keys][:creator_id]
    assert_equal :sync, policy[:public_keys][:public_pem]
    assert_equal :ineligible, policy[:public_keys][:created_at]
    assert_equal :ineligible, policy[:public_keys][:updated_at]
  end
end
