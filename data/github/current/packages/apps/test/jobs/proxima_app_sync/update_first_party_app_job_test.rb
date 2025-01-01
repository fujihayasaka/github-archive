# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "update_app_job_helper_test"

class UpdateFirstPartyAppJobTest < GitHub::TestCase
  include UpdateAppJobHelperTest

  fixtures do
    on_multi_tenant_enterprise do
      @business = create :business
      GitHub::CurrentTenant.set(@business)
      make_trusted_oauth_apps_owner # This is needed to set the trusted apps owner
      make_proxima_third_party_apps_owner
      @job_klass = ProximaAppSync::UpdateFirstPartyAppJob
      @owner_id = @job_klass.new.owner_id
      @app = create(:integration, owner: create(:user))
      @dotcom_global_id = "Q_8675309"
      @fingerprint = "fingerprint"
      @latest_fingerprint = "fingerprint_next"
      @synchronization = ProximaAppSynchronization.create!(dotcom_global_id: @dotcom_global_id, local_app: @app, fingerprint: @fingerprint)
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
    test "does not overwrite local integration's public keys" do
      @synchronization.local_app.update!(public_keys: [create(:integration_key)])

      Apps::Privileged::ApiHmacClient.any_instance
        .expects(:app_manifest)
        .with(id: @dotcom_global_id)
        .returns(
          {
            "settings" => {
              "public_keys" => [
                {
                  "public_pem" => new_pem = OpenSSL::PKey::RSA.new(2048).public_key.to_pem
                }
              ],
              "owner" => {
                "dotcom_id" => 123431,
                "dotcom_type" => "User",
                "dotcom_node_id" => "Q_1234567",
                "login" => "owner_dtcm",
                "display_login" => "owner",
                "url" => "https://owner.com",
                "avatar_url" => "https://owner.com/avatar/1"
              }
            }
          }
        )

      refute_empty @synchronization.local_app.public_keys

      @job_klass.perform_now(@dotcom_global_id, @latest_fingerprint)

      assert_equal 1, @synchronization.local_app.public_keys.size
      refute_equal new_pem, @synchronization.local_app.public_keys.first.public_pem
    end

    test "does not sync public_keys" do
      Apps::Privileged::ApiHmacClient.any_instance
        .expects(:app_manifest)
        .with(id: @dotcom_global_id)
        .returns(
          {
            "settings" => {
              "public_keys" => [
                {
                  "public_pem" => new_pem = OpenSSL::PKey::RSA.new(2048).public_key.to_pem
                }
              ],
              "owner" => {
                "dotcom_id" => 123431,
                "dotcom_type" => "User",
                "dotcom_node_id" => "Q_1234567",
                "login" => "owner_dtcm",
                "display_login" => "owner",
                "url" => "https://owner.com",
                "avatar_url" => "https://owner.com/avatar/1"
              }
            }
          }
        )

      assert_empty @synchronization.local_app.public_keys

      @job_klass.perform_now(@dotcom_global_id, @latest_fingerprint)

      assert_empty @synchronization.local_app.public_keys
    end
  end
end
