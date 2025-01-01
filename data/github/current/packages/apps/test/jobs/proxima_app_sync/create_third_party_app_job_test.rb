
# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "create_app_job_helper_test"

class CreateThirdPartyAppJobTest < GitHub::TestCase
  include CreateAppJobHelperTest

  fixtures do
    on_multi_tenant_enterprise do
      @business = create :business
      GitHub::CurrentTenant.set(@business)
      make_trusted_oauth_apps_owner
      make_proxima_third_party_apps_owner
      @job_klass = ProximaAppSync::CreateThirdPartyAppJob
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
    assert_equal "third", @job_klass.new.party_type
  end

  context "perform" do
    test "creates a third-party apps owner" do
      integration = build_internal_integration
      stub_proxima_integration_manifest_endpoint(integration)

      GitHub.proxima_third_party_apps_owner.destroy!
      assert_nil GitHub.proxima_third_party_apps_owner

      assert_difference "Organization.count", 1 do
        @job_klass.perform_now(app_global_relay_id: integration.global_relay_id)
      end

      owner = GitHub.proxima_third_party_apps_owner
      assert_predicate owner, :present?
    end

    test "syncs the integration's public keys" do
      integration = build_internal_integration
      assert_equal 1, integration.public_keys.size

      assert_difference "Integration.all.size", +1 do
        stub_proxima_integration_manifest_endpoint(integration)
        @job_klass.perform_now(app_global_relay_id: integration.global_relay_id)
      end

      synced_integration = Integration.last

      assert_equal 1, synced_integration.public_keys.size
      assert_equal integration.public_keys.first.public_pem, synced_integration.public_keys.first.public_pem
    end
  end
end
