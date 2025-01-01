# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotWorkspaceConcurrencyPolicyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  setup do
    enable_feature_flag(:copilot_workspace)
    disable_feature_flag(:codespaces_max_concurrent_cores)
    disable_feature_flag(:codespaces_automated_testing)
    @sku = Codespaces::Skus.sku_by_name(:standardLinux32gb)
  end

  context "Concurrency limits for copilot workspace codespaces are set with dials" do
    test "the maximum number of copilot workspace instances for a user is set by a dial" do
      create(:codespace, :copilot_workspace, owner: @user)
      Codespaces::Dials::MaximumCopilotWorkspaceInstancesForUser.update(2)
      policy = copilot_workspace_concurrency_policy
      assert has_capacity?(policy)
      Codespaces::Dials::MaximumCopilotWorkspaceInstancesForUser.update(1)
      policy = copilot_workspace_concurrency_policy
      refute has_capacity?(policy)
    end

    test "the maximum number of cores utilized by copilot workspace codespaces for a user is set by a dial" do
      create(:codespace, :copilot_workspace, owner: @user)
      Codespaces::Dials::MaximumCopilotWorkspaceCoresForUser.update(8)
      policy = copilot_workspace_concurrency_policy
      assert has_capacity?(policy)
      Codespaces::Dials::MaximumCopilotWorkspaceCoresForUser.update(7)
      policy = copilot_workspace_concurrency_policy
      refute has_capacity?(policy)
    end
  end

  context "Normal and CWTP codespace concurrency policies don't affect one another" do
    test "When user is at normal codespace concurrency limit, they can still create a CWTP codespace" do
      create(:codespace, owner: @user)
      Codespaces::Dials::MaximumCopilotWorkspaceInstancesForUser.update(1)
      normal_policy = normal_concurrency_policy
      refute has_capacity?(normal_policy)
      cwtp_policy = copilot_workspace_concurrency_policy
      assert has_capacity?(cwtp_policy)
    end

    test "When user is at normal codespace core limit, they can still create a CWTP codespace" do
      create(:codespace, owner: @user)
      Codespaces::Dials::MaximumCopilotWorkspaceCoresForUser.update(4)
      normal_policy = normal_concurrency_policy
      refute has_capacity?(normal_policy)
      cwtp_policy = copilot_workspace_concurrency_policy
      assert has_capacity?(cwtp_policy)
    end

    test "When user is at CWTP codespace concurrency limit, they can still create a normal codespace" do
      create(:codespace, :copilot_workspace, owner: @user)
      Codespaces::Dials::MaximumCopilotWorkspaceInstancesForUser.update(1)
      cwtp_policy = copilot_workspace_concurrency_policy
      refute has_capacity?(cwtp_policy)
      normal_policy = normal_concurrency_policy
      assert has_capacity?(normal_policy)
    end

    test "When user is at CWTP codespace core limit, they can still create a normal codespace" do
      create(:codespace, :copilot_workspace, owner: @user)
      Codespaces::Dials::MaximumCopilotWorkspaceCoresForUser.update(4)
      cwtp_policy = copilot_workspace_concurrency_policy
      refute has_capacity?(cwtp_policy)
      normal_policy = normal_concurrency_policy
      assert has_capacity?(normal_policy)
    end
  end

  test "it rescues GitHub::Redis::Mutex::LockError when encountered and reraises a CopilotWorkspaceConcurrencyLimitError" do
    GitHub::Redis::ConcurrencySafeMutex.any_instance.stubs(:lock).raises(GitHub::Redis::Mutex::LockError)
    mutex = GitHub::Redis::ConcurrencySafeMutex.new("codespaces-test-lock", wait: 0.1).unlock!
    policy = copilot_workspace_concurrency_policy(mutex: mutex)

    assert_raises Codespaces::CopilotWorkspaceConcurrencyLimitError do
      policy.reserve_capacity(sku: @sku, location: @location)
    end
  end

  def normal_concurrency_policy(user: @user, billable_owner: @user, max_concurrent_instances: 1, max_concurrent_cores: 4, mutex: FakeMutex.new)
    Codespaces::ConcurrencyPolicy.new(user, billable_owner: billable_owner, max_concurrent_instances: max_concurrent_instances, max_concurrent_cores: max_concurrent_cores, mutex: mutex)
  end

  def copilot_workspace_concurrency_policy(user: @user, billable_owner: @user, mutex: FakeMutex.new)
    Codespaces::CopilotWorkspaceConcurrencyPolicy.new(user, billable_owner: billable_owner, mutex: mutex)
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
end
