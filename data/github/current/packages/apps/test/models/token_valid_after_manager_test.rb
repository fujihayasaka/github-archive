# typed: true
# frozen_string_literal: true

require "test_helper"

class TokenValidAfterManagerTest < GitHub::TestCase
  test "returns a valid_after timestamp based on permissions replication delay" do
    GitHub.flipper[:valid_after_manager_mysql1_replication_delay].disable
    ApplicationRecord::Permissions.stubs(:default_replication_wait).returns(3500.0)

    installation = ScopedIntegrationInstallation.new

    now = Time.utc(2023, 3, 8)
    # calculated as: now.to_f + (3500.0/1000) = 1678233600.0 + 3.5
    expected_valid_after = 1678233603.5
    Timecop.freeze(now) do
      valid_after = TokenValidAfterManager.new(installation).valid_after
      assert_equal expected_valid_after, valid_after
    end
  end

  test "returns a valid_after timestamp considering permissions and mysql1 delay if ff enabled" do
    GitHub.flipper[:valid_after_manager_mysql1_replication_delay].enable
    installation = ScopedIntegrationInstallation.new

    now = Time.utc(2023, 3, 8)
    ApplicationRecord::Permissions.stubs(:default_replication_wait).returns(3500.0)
    # In this case the delay on permissions is greater than the delay on mysql1.
    ApplicationRecord::Domain::IntegrationsLodge.stubs(:default_replication_wait).returns(1000.0)
    # calculated as: now.to_f + (3500.0/1000) = 1678233600.0 + 3.5
    expected_valid_after = 1678233603.5
    Timecop.freeze(now) do
      valid_after = TokenValidAfterManager.new(installation).valid_after
      assert_equal expected_valid_after, valid_after
    end

    # In this case the delay on mysql1 is greater than the delay on permissions.
    ApplicationRecord::Domain::IntegrationsLodge.stubs(:default_replication_wait).returns(5000.0)
    # calculated as: now.to_f + (5000.0/1000) = 1678233600.0 + 5.0
    expected_valid_after = 1678233605.0
    Timecop.freeze(now) do
      valid_after = TokenValidAfterManager.new(installation).valid_after
      assert_equal expected_valid_after, valid_after
    end
  end

  context "when the installation is cached" do
    test "returns now as valid_after if the mysql1 ff is disabled" do
      GitHub.flipper[:valid_after_manager_mysql1_replication_delay].disable
      ApplicationRecord::Permissions.stubs(:default_replication_wait).returns(3500.0)

      installation = ScopedIntegrationInstallation.new
      now = Time.utc(2023, 3, 8)
      # because the installation is cached, we can assume that the permissions are already
      # replicated to the permissions cluster.
      # calculated as: now.to_f = 1678233600.0
      expected_valid_after = 1678233600.0
      Timecop.freeze(now) do
        valid_after = TokenValidAfterManager.new(installation, using_cached_installation: true).valid_after
        assert_equal expected_valid_after, valid_after
      end
    end

    test "returns a valid_after timestamp considering mysql1 if ff is enabled" do
      GitHub.flipper[:valid_after_manager_mysql1_replication_delay].enable
      ApplicationRecord::Permissions.stubs(:default_replication_wait).returns(3500.0)
      ApplicationRecord::Domain::IntegrationsLodge.stubs(:default_replication_wait).returns(1500.0)

      installation = ScopedIntegrationInstallation.new
      now = Time.utc(2023, 3, 8)
      # Although the installation is cached, we have to account for the delay on mysql1.
      # calculated as: now.to_f + (1500.0/1000) = 1678233600.0 + 1.5
      expected_valid_after = 1678233601.5
      Timecop.freeze(now) do
        valid_after = TokenValidAfterManager.new(installation, using_cached_installation: true).valid_after
        assert_equal expected_valid_after, valid_after
      end
    end
  end

  test "stats when mysql1 ff is disabled" do
    GitHub.flipper[:valid_after_manager_mysql1_replication_delay].disable

    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    ApplicationRecord::Permissions.stubs(:default_replication_wait).returns(3500.0)

    now = Time.utc(2023, 3, 8)
    expected_delay = 3500.0
    Timecop.freeze(now) do
      installation = ScopedIntegrationInstallation.new
      TokenValidAfterManager.new(installation).valid_after
      expected_tags = ["token_type:scoped_integration_installation", "cached_installation:false", "delaying_cluster:permissions"]
      assert_equal expected_delay, GitHub.dogstats.distributions("apps.token_valid_after_manager.delay", tags: expected_tags).last.value

      installation = SiteScopedIntegrationInstallation.new
      TokenValidAfterManager.new(installation, using_cached_installation: true).valid_after
      expected_tags = ["token_type:site_scoped_integration_installation", "cached_installation:true", "delaying_cluster:permissions"]
      # Because the installation is cached, the expected delay is 0.0.
      assert_equal 0.0, GitHub.dogstats.distributions("apps.token_valid_after_manager.delay", tags: expected_tags).last.value

      installation = IntegrationInstallation.new(created_at: 1.week.ago)
      TokenValidAfterManager.new(installation).valid_after
      expected_tags = ["token_type:integration_installation", "cached_installation:false", "delaying_cluster:permissions"]
      # Because this is an "old" installation, the expected delay is 0.0.
      assert_equal 0.0, GitHub.dogstats.distributions("apps.token_valid_after_manager.delay", tags: expected_tags).last.value
    end
  end

  test "stats when mysql1 ff is enabled" do
    GitHub.flipper[:valid_after_manager_mysql1_replication_delay].enable

    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    ApplicationRecord::Permissions.stubs(:default_replication_wait).returns(3500.0)
    ApplicationRecord::Domain::IntegrationsLodge.stubs(:default_replication_wait).returns(2500.0)

    now = Time.utc(2023, 3, 8)
    Timecop.freeze(now) do
      installation = ScopedIntegrationInstallation.new
      TokenValidAfterManager.new(installation).valid_after
      expected_tags = ["token_type:scoped_integration_installation", "cached_installation:false", "delaying_cluster:permissions"]
      assert_equal 3500.0, GitHub.dogstats.distributions("apps.token_valid_after_manager.delay", tags: expected_tags).last.value

      installation = SiteScopedIntegrationInstallation.new
      TokenValidAfterManager.new(installation, using_cached_installation: true).valid_after
      expected_tags = ["token_type:site_scoped_integration_installation", "cached_installation:true", "delaying_cluster:mysql1"]
      # Although the installation is cached, we have to account for the delay on mysql1.
      assert_equal 2500.0, GitHub.dogstats.distributions("apps.token_valid_after_manager.delay", tags: expected_tags).last.value

      installation = IntegrationInstallation.new(created_at: 1.week.ago)
      TokenValidAfterManager.new(installation).valid_after
      expected_tags = ["token_type:integration_installation", "cached_installation:false", "delaying_cluster:mysql1"]
      # Although this is an "old" installation, we have to account for the delay on mysql1.
      assert_equal 2500.0, GitHub.dogstats.distributions("apps.token_valid_after_manager.delay", tags: expected_tags).last.value
    end
  end
end
