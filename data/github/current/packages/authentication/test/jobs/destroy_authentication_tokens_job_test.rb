# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/dogstats_test_helpers"

class DestroyAuthenticationTokensJobTest < GitHub::TestCase
  include JobTestHelper
  include DogstatsTestHelpers

  setup do
    disable_feature_flag(:disabled_global_apps)
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    @installation = create(:integration_installation)
    @user       = create(:user)
    @repository = create(:repository, :minimal, owner: @user)

    @integration = @installation.integration
    @scoped_installation = make_scoped_integration_installation(parent: make_integration_installation(integration: @integration,
      target: @user, permissions: { "metadata" => :read }), repositories: [@repository])
    @site_scoped_installation = make_site_scoped_integration_installation(integration: create_unlimited_global_integration, target: @user, repositories: [@repository])
    1.times { @installation.generate_token }
  end

  test "should destroy authentication tokens by authenticatable_id" do
    assert_equal 1, ServerToServerTokens.domain.count_by_authenticatable_id(@installation.id)

    DestroyAuthenticationTokensJob.perform_now(@installation.id, "IntegrationInstallation")
    assert_empty ServerToServerTokens.domain.by_authenticatable_id(@installation.id)
  end

  test "should destroy scoped authentication tokens by authenticatable_id" do
    2.times { @scoped_installation.generate_token }
    assert_equal 2, ServerToServerTokens.domain.count_by_authenticatable_id(@scoped_installation.id)

    DestroyAuthenticationTokensJob.perform_now(@scoped_installation.id, "ScopedIntegrationInstallation")
    assert_empty ServerToServerTokens.domain.by_authenticatable_id(@scoped_installation.id)
  end

  test "should destroy site-scoped authentication tokens by authenticatable_id" do
    3.times { @site_scoped_installation.generate_token }
    assert_equal 3, ServerToServerTokens.domain.count_by_authenticatable_id(@site_scoped_installation.id)

    DestroyAuthenticationTokensJob.perform_now(@site_scoped_installation.id, "SiteScopedIntegrationInstallation")
    assert_empty ServerToServerTokens.domain.by_authenticatable_id(@site_scoped_installation.id)
  end

  test "should handle ActiveRecord::RecordNotFound" do
    assert_nothing_raised do
      DestroyAuthenticationTokensJob.perform_now(-1, "IntegrationInstallation")
    end
  end

  test "retries the job if a throttling error occurs" do
    assert_retry_on_throttler_error job: DestroyAuthenticationTokensJob, args: [@installation.id, "IntegrationInstallation"]
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: DestroyAuthenticationTokensJob, args: [@installation.id, "IntegrationInstallation"]
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: DestroyAuthenticationTokensJob, args: [@installation.id, "IntegrationInstallation"]
  end

  test "retries some expected error classes" do
    [
      ActiveRecord::AdapterTimeout,
      ActiveRecord::ConnectionFailed,
      ActiveRecord::ConnectionNotEstablished,
    ].each do |error|
      assert_retry_on_error(
        error,
        DestroyAuthenticationTokensJob,
        [@installation.id, "IntegrationInstallation"],
      )
    end
  end

  test "emits metrics for total and destroyed records" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    DestroyAuthenticationTokensJob.perform_now(@installation.id, "IntegrationInstallation")

    assert_dogstats_distribution("authentication_tokens.to_destroy.total", value: 2, tags: ["authenticatable_class:IntegrationInstallation"])
    assert_dogstats_distribution("authentication_tokens.destroyed.total", value: 2, tags: ["authenticatable_class:IntegrationInstallation"])
  end

  test "emits metrics for total and destroyed records for other installation class names" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    @site_scoped_installation.generate_token

    DestroyAuthenticationTokensJob.perform_now(@site_scoped_installation.id, "SiteScopedIntegrationInstallation")

    assert_dogstats_distribution("authentication_tokens.to_destroy.total", value: 2, tags: ["authenticatable_class:SiteScopedIntegrationInstallation"])
    assert_dogstats_distribution("authentication_tokens.destroyed.total", value: 2, tags: ["authenticatable_class:SiteScopedIntegrationInstallation"])
  end

  test "emits partial destroy metric if not all records are destroyed" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    ServerToServerTokens::Domain.any_instance.stubs(:count_by_authenticatable_id).with(@installation.id).returns(2)
    ServerToServerTokens::Domain.any_instance.stubs(:destroy_by_authenticatable_id).with(@installation.id).returns(GH::Result::Ok.new(1))

    DestroyAuthenticationTokensJob.perform_now(@installation.id, "IntegrationInstallation")

    assert_dogstats_distribution("authentication_tokens.to_destroy.total", value: 2, tags: ["authenticatable_class:IntegrationInstallation"])
    assert_dogstats_distribution("authentication_tokens.destroyed.total", value: 1, tags: ["authenticatable_class:IntegrationInstallation"])
    assert_dogstats_distribution("authentication_tokens.destroy.partial", value: 1, tags: ["authenticatable_class:IntegrationInstallation"])
  end

  test "emits count missing metric if total records count is missing" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    ServerToServerTokens::Domain.any_instance.stubs(:count_by_authenticatable_id).with(-1).returns(nil)

    DestroyAuthenticationTokensJob.perform_now(-1, "IntegrationInstallation")

    assert_dogstats_increment(1, "authentication_tokens.to_destroy.count_missing", tags: ["authenticatable_class:IntegrationInstallation"])
  end
end
