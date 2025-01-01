# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RepositoryDiskUsageJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper

  fixtures do
    @repo = create(:repository)
  end

  test "returns early when repo to be processed does not exist" do
    result = RepositoryDiskUsageJob.perform_now(12345)
    assert_nil result
  end

  test "returns disk usage on the repository passed to job" do
    Repository.any_instance.stubs(:exists_on_disk?).returns(:foo)
    GitRPC::Client.any_instance.stubs(:repo_disk_usage).returns(63716)
    result = RepositoryDiskUsageJob.perform_now(@repo.id)

    assert_equal 62, result
  end

  test "returns nil on a GitRPC::Protocol::DGit::ResponseError" do
    Repository.any_instance.stubs(:update_disk_usage).raises(GitRPC::Protocol::DGit::ResponseError, "test error")
    expected_payload = {
      "exception.message" => "test error",
      "code.namespace" => "RepositoryDiskUsageJob",
      "code.function" => "perform",
      "gh.repo.id" => @repo.id
    }
    assert_logged(**expected_payload) do
      result = RepositoryDiskUsageJob.perform_now(@repo.id)
      assert_nil result
    end
  end

  test "resolves tenant on a multi-tenant enterprise" do
    on_multi_tenant_enterprise do
      user = create(:emu)
      GitHub::CurrentTenant.set(user.enterprise_managed_business)
      repo = create(:repository, owner: user, from_example: :simple)

      # Simulate no tenant being set
      GitHub::CurrentTenant.remove
      assert_nil GitHub::CurrentTenant.get
      refute_predicate GitHub::CurrentTenant, :unscoped?

      Repositories::Public.expects(:resolve_tenant).at_least_once.with(id: repo.id).returns(user.enterprise_managed_business)
      result = RepositoryDiskUsageJob.perform_now(repo.id)
    end
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: RepositoryDiskUsageJob, args: [@repo.id]
  end
end
