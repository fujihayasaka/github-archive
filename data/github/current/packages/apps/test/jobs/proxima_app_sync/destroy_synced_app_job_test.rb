
# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "create_app_job_helper_test"

class DestroySyncedAppJobTest < GitHub::TestCase

  fixtures do
    on_multi_tenant_enterprise do
      @business = create :business
      GitHub::CurrentTenant.set(@business)
      @job_klass = ProximaAppSync::DestroySyncedAppJob
      @dotcom_global_id = "Q_8675309"
      @fingerprint = "fingerprint"
      @latest_fingerprint = "fingerprint_next"
    end
  end

  setup do
    on_multi_tenant_enterprise
    GitHub::CurrentTenant.set(@business)
  end

  teardown do
    GitHub::CurrentTenant.remove
  end

  context "perform" do
    test "destroys oauth application sync records" do
      oauth_application = create(:oauth_application)
      sync_record = ProximaAppSynchronization.create!(dotcom_global_id: @dotcom_global_id, local_app: oauth_application, fingerprint: @fingerprint)
      @job_klass.perform_now(dotcom_global_id: sync_record.dotcom_global_id)
      assert_nil OauthApplication.find_by(id: oauth_application.id)
      assert_nil ProximaAppSynchronization.find_by(id: sync_record.id)
    end

    test "destroys integration sync records" do
      integration = create(:integration)
      sync_record = ProximaAppSynchronization.create!(dotcom_global_id: @dotcom_global_id, local_app: integration, fingerprint: @fingerprint)
      @job_klass.perform_now(dotcom_global_id: sync_record.dotcom_global_id)
      assert_nil Integration.find_by(id: integration.id)
      assert_nil ProximaAppSynchronization.find_by(id: sync_record.id)
    end
  end
end
