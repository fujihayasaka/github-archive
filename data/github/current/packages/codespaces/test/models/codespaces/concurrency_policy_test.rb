# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesConcurrencyPolicyTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user, :with_codespaces_basic_tier_access)
    disable_feature_flag(:codespaces_linux_premium_gpu, @user)
    disable_feature_flag(:codespaces_max_concurrent_cores, @user)
    @codespace = create(:codespace, owner: @user)
    @sku = Codespaces::Skus.sku_by_name(:standardLinux32gb)
    @mutex = FakeMutex.new
    @raising_mutex = RaisingMutex.new
    @location = "WestUs2"
  end

  setup do
    disable_feature_flag(:codespaces_automated_testing)
  end

  context "#reserve_capacity without tier feature flag" do
    test "it enforces the instance limit" do
      assert has_capacity?(created_custom_policy)
      refute has_capacity?(created_custom_policy(max_concurrent_instances: 1))
    end

    test "it enforces the core limit" do
      assert has_capacity?(created_custom_policy)
      refute has_capacity?(created_custom_policy(max_concurrent_cores: 1))
    end

    test "it ignores automated test accounts" do
      enable_feature_flag(:codespaces_automated_testing, @user)

      assert has_capacity?(created_custom_policy(max_concurrent_instances: 0, max_concurrent_cores: 0))
    end

    test "it respects the lock" do
      mutex = GitHub::Redis::ConcurrencySafeMutex.new("codespaces-test-lock", wait: 0.1).unlock!
      assert mutex.lock

      block_called = T.let(false, T::Boolean)
      assert_raises Codespaces::ConcurrencyLimitError do
        policy = created_custom_policy(mutex: mutex)
        policy.reserve_capacity(sku: @sku, location: @location) do
          block_called = true
        end
      end
      refute block_called
    end

    test "it rescues GitHub::Redis::Mutex::LockError when encountered and reraises a ConcurrencyLimitError" do
      GitHub::Redis::ConcurrencySafeMutex.any_instance.stubs(:lock).raises(GitHub::Redis::Mutex::LockError)
      mutex = GitHub::Redis::ConcurrencySafeMutex.new("codespaces-test-lock", wait: 0.1).unlock!
      policy = created_custom_policy(mutex: mutex)

      assert_raises Codespaces::ConcurrencyLimitError do
        policy.reserve_capacity(sku: @sku, location: @location)
      end
    end
  end

  context "#reserve_capacity with tier feature flag" do
    test "respects concurrent codespace limits set by tier 3" do

      expected_tier = TrustTiers::Tier::UNTRUSTED
      Codespaces::Tier.stubs(:for_user).returns(TrustTiers::TierResult.new(expected_tier, "reason"))
      assert has_capacity?(created_default_policy)
      create(:codespace, owner: @user)
      refute has_capacity?(created_default_policy)
    end

    test "respects concurrent codespace limits set by tier 1" do

      expected_tier = TrustTiers::Tier::TRUSTED
      Codespaces::Tier.stubs(:for_user).returns(TrustTiers::TierResult.new(expected_tier, "reason"))
      assert has_capacity?(created_default_policy)
      create(:codespace, owner: @user)
      assert has_capacity?(created_default_policy)
      (Codespaces::Tier.get_config_map(@user)[expected_tier].concurrent_codespaces - 2).times do # -2 because we created one in the fixture and one in this test
        create(:codespace, owner: @user)
      end
      refute has_capacity?(created_default_policy)
    end

    test "respects concurrent core limits set by tier 1" do
      disable_feature_flag(:codespaces_linux_premium_gpu, @user)

      expected_tier = TrustTiers::Tier::TRUSTED
      Codespaces::Tier.stubs(:for_user).returns(TrustTiers::TierResult.new(expected_tier, "reason"))
      assert has_capacity?(created_default_policy)

      # extremeLinux has 32 cores so tier 1 has a limit of 2
      create(:codespace, owner: @user, sku_name: :extremeLinux)

      refute has_capacity?(created_default_policy, sku: Codespaces::Skus.sku_by_name(:extremeLinux))
    end
  end

  context "recording limit hits" do
    test "it records when the limit is hit" do
      policy = created_custom_policy(max_concurrent_instances: 0)

      logger_output = {
        "Body" => "Codespace concurrency limit hit",
        "gh.catalog_service" => "github/codespaces",
        "gh.codespaces.owner_id" => @user.id,
        "gh.codespaces.billable_owner_id" => @user.id,
        "gh.codespaces.region" => @location,
        "gh.codespaces.sku_name" => @sku.name,
      }
      assert_logged(**logger_output) do
        refute has_capacity?(policy)
      end

      assert_dogstats_increment(1, "codespaces.concurrency_policy.limit_hit")
    end

    test "it records even when the block raises" do
      policy = created_custom_policy(max_concurrent_instances: 0)

      logger_output = {
        "Body" => "Codespace concurrency limit hit",
        "gh.catalog_service" => "github/codespaces",
        "gh.codespaces.owner_id" => @user.id,
        "gh.codespaces.billable_owner_id" => @user.id,
        "gh.codespaces.region" => @location,
        "gh.codespaces.sku_name" => @sku.name,
      }

      assert_raises RuntimeError do
        assert_logged(**logger_output) do
          policy.reserve_capacity(sku: @sku, location: @location) do
            raise "oh no"
          end
        end
      end

      assert_dogstats_increment(1, "codespaces.concurrency_policy.limit_hit")
    end

    test "it records when we hit a lock error" do
      policy = created_default_policy(mutex: @raising_mutex)

      logger_output = {
        "Body" => "Codespace concurrency lock error hit",
        "gh.catalog_service" => "github/codespaces",
        "gh.codespaces.owner_id" => @user.id,
        "gh.codespaces.billable_owner_id" => @user.id,
        "gh.codespaces.region" => @location,
        "gh.codespaces.sku_name" => @sku.name,
      }

      assert_raises Codespaces::ConcurrencyLimitError do
        assert_logged(**logger_output) do
          refute has_capacity?(policy)
        end
      end

      assert_dogstats_increment(1, "codespaces.concurrency_policy.lock_error_hit")
    end
  end

  test "it has a higher concurrent core limit when codespaces_max_concurrent_cores is enabled for the user" do
    enable_feature_flag(:codespaces_max_concurrent_cores, @user)
    assert_equal Codespaces::ConcurrencyPolicy::MAX_CONCURRENT_CORES_INTERNAL, created_default_policy.max_concurrent_cores

    disable_feature_flag(:codespaces_max_concurrent_cores, @user)
    assert_operator Codespaces::ConcurrencyPolicy::MAX_CONCURRENT_CORES_INTERNAL, :>, created_default_policy.max_concurrent_cores
  end

  test "it has a higher concurrent core limit when codespaces_max_concurrent_cores is enabled with tiering enabled" do
    Codespaces::Tier.stubs(:for_user).returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
    enable_feature_flag(:codespaces_max_concurrent_cores, @user)

    assert_equal Codespaces::ConcurrencyPolicy::MAX_CONCURRENT_CORES_INTERNAL, created_default_policy.max_concurrent_cores
  end

  test "it has a higher concurrent core limit when the GPU SKU is enabled for the user" do
    enable_feature_flag(:codespaces_linux_premium_gpu, @user)
    assert_equal Codespaces::ConcurrencyPolicy::MAX_CONCURRENT_CORES_WITH_GPU, created_default_policy.max_concurrent_cores

    disable_feature_flag(:codespaces_linux_premium_gpu, @user)
    assert_operator Codespaces::ConcurrencyPolicy::MAX_CONCURRENT_CORES_WITH_GPU, :>, created_default_policy.max_concurrent_cores
  end

  test "it has a higher concurrent core limit when the GPU SKU is enabled with tiering enabled" do
    Codespaces::Tier.stubs(:for_user).returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
    enable_feature_flag(:codespaces_linux_premium_gpu, @user)

    assert_equal Codespaces::ConcurrencyPolicy::MAX_CONCURRENT_CORES_WITH_GPU, created_default_policy.max_concurrent_cores
  end

  context "enforce_concurrency_limits!" do
    test "stops codespaces over the limit" do
      Codespaces::VscsClient.any_instance.expects(:shutdown_environment).with(@codespace.guid, repository: @codespace.repository, billable_owner: @codespace.billable_owner).returns(nil)
      policy = created_custom_policy(max_concurrent_instances: 0)
      stopped_count = policy.enforce_concurrency_limits!

      assert_equal 1, stopped_count
    end

    test "stops the least recently used" do
      other_codespace = create(:codespace, owner: @user, last_used_at: 2.days.ago)

      Codespaces::VscsClient.any_instance.expects(:shutdown_environment).with(other_codespace.guid, repository: other_codespace.repository, billable_owner: other_codespace.billable_owner).returns(nil)
      policy = created_custom_policy(max_concurrent_instances: 1)
      stopped_count = policy.enforce_concurrency_limits!

      assert_equal 1, stopped_count
    end

    test "as many codespaces as needed to get under the limit" do
      codespace_1 = create(:codespace, owner: @user, last_used_at: 1.day.ago)
      codespace_2 = create(:codespace, owner: @user, last_used_at: 2.days.ago)

      Codespaces::VscsClient.any_instance.expects(:shutdown_environment).with(codespace_1.guid, repository: codespace_1.repository, billable_owner: codespace_1.billable_owner).returns(nil)
      Codespaces::VscsClient.any_instance.expects(:shutdown_environment).with(codespace_2.guid, repository: codespace_2.repository, billable_owner: codespace_2.billable_owner).returns(nil)
      policy = created_custom_policy(max_concurrent_instances: 1)
      stopped_count = policy.enforce_concurrency_limits!

      assert_equal 2, stopped_count
    end

    test "does nothing if under the limit" do
      codespace_1 = create(:codespace, owner: @user, last_used_at: 1.day.ago)
      codespace_2 = create(:codespace, owner: @user, last_used_at: 2.days.ago)

      Codespaces::VscsClient.any_instance.expects(:shutdown_environment).with(@codespace.guid, repository: @codespace.repository, billable_owner: @codespace.billable_owner).never
      Codespaces::VscsClient.any_instance.expects(:shutdown_environment).with(codespace_1.guid, repository: codespace_1.repository, billable_owner: codespace_1.billable_owner).never
      Codespaces::VscsClient.any_instance.expects(:shutdown_environment).with(codespace_2.guid, repository: codespace_2.repository, billable_owner: codespace_2.billable_owner).never
      policy = created_custom_policy(max_concurrent_instances: 3)
      stopped_count = policy.enforce_concurrency_limits!

      assert_equal 0, stopped_count
    end

    test "ignores users with codespaces_automated_testing enabled" do
      enable_feature_flag(:codespaces_automated_testing, @user)

      Codespaces::VscsClient.any_instance.expects(:shutdown_environment).with(@codespace.guid, repository: @codespace.repository, billable_owner: @codespace.billable_owner).never
      policy = created_custom_policy(max_concurrent_instances: 0)
      stopped_count = policy.enforce_concurrency_limits!

      assert_equal 0, stopped_count
    end
  end

  def created_custom_policy(max_concurrent_instances: Float::INFINITY, max_concurrent_cores: Float::INFINITY, mutex: @mutex)
    Codespaces::ConcurrencyPolicy.new(
      @user,
      billable_owner: @user,
      max_concurrent_instances: max_concurrent_instances,
      max_concurrent_cores: max_concurrent_cores,
      mutex: mutex
    )
  end

  def created_default_policy(billable_owner: @user, mutex: @mutex)
    Codespaces::ConcurrencyPolicy.new(
      @user,
      billable_owner: billable_owner,
      mutex: mutex
    )
  end

  def has_capacity?(policy, sku: @sku)
    has_capacity = T.let(false, T::Boolean)
    policy.reserve_capacity(sku: sku, location: @location) do |h|
      has_capacity = h
    end
    has_capacity
  end

  class FakeMutex
    def lock
      yield
    end
  end

  class RaisingMutex
    def lock
      raise GitHub::Redis::Mutex::LockError.new("Could not acquire exclusive lock")
    end
  end
end
