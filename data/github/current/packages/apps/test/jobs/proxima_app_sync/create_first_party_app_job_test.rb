
# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "create_app_job_helper_test"

class CreateFirstPartyAppJobTest < GitHub::TestCase
  include CreateAppJobHelperTest

  fixtures do
    on_multi_tenant_enterprise do
      @business = create :business
      GitHub::CurrentTenant.set(@business)
      make_trusted_oauth_apps_owner
      make_proxima_third_party_apps_owner
      @job_klass = ProximaAppSync::CreateFirstPartyAppJob
      @owner_id = @job_klass.new.owner_id
    end
  end

  setup do
    on_multi_tenant_enterprise
    GitHub::CurrentTenant.set(@business)
  end

  teardown do
    GitHub::CurrentTenant.remove
  end

  test "party_type" do
    assert_equal "first", @job_klass.new.party_type
  end

  context "public_keys" do
    test "does not sync public key" do
      integration = build_internal_integration
      assert_predicate integration.public_keys, :present?

      assert_difference "Integration.all.size", +1 do
        stub_proxima_integration_manifest_endpoint(integration)
        @job_klass.perform_now(app_global_relay_id: integration.global_relay_id)
      end

      synced_integration = Integration.last

      assert_predicate synced_integration.public_keys, :empty?
    end
  end

  test "creates a proxima app with a tenant scoped url" do
    GitHub.flipper[:templatize_integration_url].enable

    secret = "33sfs33967a56"
    name = "fp-integration-#{SecureRandom.hex(8)}"
    integration = build(
      :integration,
      id: 1,
      name: name,
      slug: name,
      owner_id: @owner_id,
      url: "http://{hostname}.com",
      setup_url: "http://{hostname}.com",
      deleted_at: Time.utc(2023, 7, 25),
      suspended_at: Time.utc(2023, 7, 25),
      request_oauth_on_install: true,
      user_token_expiration: 1,
      key: SecureRandom.hex(8),
      pinned_api_version: GitHub.api_versions.last,
      note: "Example Note",
      default_permissions: { "metadata" => :read, "single_file" => :read },
      default_events: ["label"],
      single_file_name: "example.txt",
      device_flow_enabled: true,
      application_callback_urls: [build(:application_callback_url, url: "https://{hostname}/callback")],
      hook: build(:hook, active: true, confirmed: true, pinned_api_version: GitHub.api_versions.last, secret: "Example Secret", url: "https://{hostname}/callback"),
      integration_install_triggers: [build(:integration_install_trigger, path: "https://{hostname}.com", reason: "Example Reason")],
      ip_allowlist_entries: [build(:ip_allowlist_entry, name: "Example IP Allowlist Entry", allow_list_value: "2001:db8::/48", range_from: " \x01\r\xB8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", range_to: " \x01\r\xB8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")],
      client_secrets: [build(:integration_client_secret, secret_hash: IntegrationClientSecret.hash_for(secret), secret_last_eight: secret.last(8))],
      public_keys: [build(:integration_key)],
      bot: build(:bot)
    )

    assert_difference "Integration.all.size", +1 do
      stub_proxima_integration_manifest_endpoint(integration)
      @job_klass.perform_now(app_global_relay_id: integration.global_relay_id)
    end
  end
end
