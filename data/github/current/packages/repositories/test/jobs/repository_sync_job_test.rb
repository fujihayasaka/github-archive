# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositorySyncJobTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
  end

  test "retries on insufficient quorum error" do
    GitRPC::Client.any_instance.stubs(:nw_sync).raises(GitRPC::Protocol::DGit::ResponseError.new("Backend insufficient quorum")).then.returns(nil)

    assert_performed_jobs(2, only: RepositorySyncJob) do
      RepositorySyncJob.perform_later(@repo.id)
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
      RepositorySyncJob.perform_now(repo.id)
    end
  end
end
