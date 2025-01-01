# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RepositorySetLicenseJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @three_licenses_repo = create(:repository, owner: @user, from_example: :three_licenses)

  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: RepositorySetLicenseJob, args: [@repo]
  end

  test "sets the license on the repository" do
    repo = create(:repository, owner: @user)
    repo.license_template = "mit"
    repo.created_by_user_id = @user.id
    repo.initialize_git_repository_templates

    RepositorySetLicenseJob.perform_now(repo)

    assert_equal License["mit"], repo.reload.repository_license.license
  end

  test "sets the license on the repository when exempted from tenant" do
    on_multi_tenant_enterprise do
      repo = create(:repository, owner: @user)
      repo.license_template = "mit"
      repo.created_by_user_id = @user.id
      repo.initialize_git_repository_templates

      GitHub::CurrentTenant.reset
      RepositorySetLicenseJob.perform_now(repo)

      assert_equal License["mit"], repo.reload.repository_license.license
    end
  end

  test "doesn't throw if repo is deleted" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    perform_enqueued_jobs(only: [RepositorySetLicenseJob]) do
      RepositorySetLicenseJob.perform_later(@repo.destroy)
    end

    assert_equal 1, GitHub.dogstats.increments("active_job.discard").length
  end

  context "multiple licenses" do
    test "creates multiple licenses" do
      RepositorySetLicenseJob.perform_now(@three_licenses_repo)

      assert_equal 3, @three_licenses_repo.reload.repository_licenses.count
    end
  end
end
