# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class IntegrationClientSecretAccessJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @user = create(:user)
    @integration = create(:integration)
    @integration.generate_client_secret(creator: @user).secret
    @integration_client_secret = @integration.client_secrets.first
    @integration.grant(@user, entry_point: :test_case)
  end

  setup do
    reset_cache
    enable_cache_storage
  end

  teardown do
    disable_cache_storage
  end

  test "updates timestamp for integration client secret and sets write prevention memcached key" do
    Timecop.freeze do
      now = Time.now
      accessed_at = now.to_i - 10
      assert_nil @integration_client_secret.accessed_at

      IntegrationClientSecretAccessJob.perform_now(@integration_client_secret.id, accessed_at)

      assert_equal accessed_at, @integration_client_secret.reload.accessed_at.to_i
      refute_nil GitHub.cache.get("github:jobs:integration_client_secret_access:#{@integration_client_secret.id}")
    end
  end

  test "does not update timestamp for integration client secret if memcached key exists" do
    Timecop.freeze do
      now = Time.now
      accessed_at = now.to_i - 10
      key = "github:jobs:integration_client_secret_access:#{@integration_client_secret.id}"
      GitHub.cache.add(key, now, 0)

      assert_nil @integration_client_secret.accessed_at
      IntegrationClientSecretAccessJob.perform_now(@integration_client_secret.id, accessed_at)
      assert_nil @integration_client_secret.reload.accessed_at
    end
  end

  test "does not set memcached key if ttl is <= 0 as there is no point" do
    Timecop.freeze do
      now = Time.now
      accessed_at = now.to_i - IntegrationClientSecret::ACCESS_THROTTLING
      assert_nil @integration_client_secret.accessed_at

      IntegrationClientSecretAccessJob.perform_now(@integration_client_secret.id, accessed_at)

      assert_nil GitHub.cache.get("github:jobs:integration_client_secret_access:#{@integration_client_secret.id}")
      assert_equal accessed_at, @integration_client_secret.reload.accessed_at.to_i
    end
  end

  test "retry conditions" do
    now = Time.now
    assert_retry_on_dirty_exit job: IntegrationClientSecretAccessJob, args: [@integration_client_secret.id, now]
  end
end
