# typed: true
# frozen_string_literal: true

require "test_helper"

class WorkspaceEditor::CloudspaceConcurrencyLimiterTest < GitHub::TestCase
  fixtures do
    GitHub.flipper[:codespaces_max_concurrent_cores].disable
    GitHub.flipper[:codespaces_automated_testing].disable

    @user = create(:user)
    create(:feature_with_flipper, :opt_out, slug: "copilot_hadron_editor")
    GitHub.flipper[:copilot_hadron_editor].enable
    @user.enable_feature_preview(:copilot_hadron_editor)
  end

  setup do
    @sku = Codespaces::Skus.sku_by_name(:standardLinux32gb)
  end

  context "Concurrency limits for workspace editor cloudspaces are set with dials" do
    test "the maximum number of cloudspace instances for a user is set by a dial" do
      create(:workspace_editor_cloud_environment, owner: @user)
      WorkspaceEditor::Cloudspaces::Dials::MaximumInstancesForUser.update(2)
      policy = workspace_editor_cloudspaces_concurrency_policy
      assert has_capacity?(policy)
      WorkspaceEditor::Cloudspaces::Dials::MaximumInstancesForUser.update(1)
      policy = workspace_editor_cloudspaces_concurrency_policy
      refute has_capacity?(policy)
    end
  end

  context "Codespace and Workspace Editor concurrency policies don't affect one another" do
    test "When user is at codespace concurrency limit, they can still create a workspace editor cloudspace" do
      create(:codespace, owner: @user)
      WorkspaceEditor::Cloudspaces::Dials::MaximumInstancesForUser.update(1)
      codespace_policy = codespaces_concurrency_policy
      refute has_capacity?(codespace_policy)
      hadron_policy = workspace_editor_cloudspaces_concurrency_policy
      assert has_capacity?(hadron_policy)
    end

    test "When user is at the workspace editor cloudspace concurrency limit, they can still create a normal codespace" do
      create(:workspace_editor_cloud_environment, owner: @user)
      WorkspaceEditor::Cloudspaces::Dials::MaximumInstancesForUser.update(1)
      hadron_policy = workspace_editor_cloudspaces_concurrency_policy
      refute has_capacity?(hadron_policy)
      codespace_policy = codespaces_concurrency_policy
      assert has_capacity?(codespace_policy)
    end
  end

  def workspace_editor_cloudspaces_concurrency_policy(user: @user, billable_owner: @user, mutex: FakeMutex.new)
    WorkspaceEditor::Cloudspaces::ConcurrencyLimiter.new(user, billable_owner: billable_owner, mutex: mutex)
  end

  def codespaces_concurrency_policy(user: @user, billable_owner: @user, max_concurrent_instances: 1, max_concurrent_cores: 4, mutex: FakeMutex.new)
    Codespaces::ConcurrencyPolicy.new(user, billable_owner: billable_owner, max_concurrent_instances: max_concurrent_instances, max_concurrent_cores: max_concurrent_cores, mutex: mutex)
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
