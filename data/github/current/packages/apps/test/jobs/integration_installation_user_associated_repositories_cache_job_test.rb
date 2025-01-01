# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class IntegrationInstallationUserAssociatedRepositoriesCacheJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @org = create(:organization)
    @admin = @org.admins.first
    @member = create(:user)
    @org.add_member(@member)
    @repo = create(:repository, :minimal, owner: @org)
    @repo_1 = create(:repository, :minimal, owner: @org)
    @installation = make_integration_installation(target: @org, repositories: [@repo, @repo_1], permissions: { "metadata" => :read })
  end

  test "cache is invalidated when installed on an organization", skip_enterprise: true do
    Flipper[:installation_user_associated_repo_ids_cache].enable(@installation.integration)

    with_cache_enabled(/installation:user:repo_ids/) do
      GitHub.cache.set(
        IntegrationInstallation::UserAssociatedRepositories.cache_key(@member, @installation),
        [@repo.id, @repo_1.id].to_json
      )
      GitHub.cache.set(
        IntegrationInstallation::UserAssociatedRepositories.cache_key(@admin, @installation),
        [@repo.id, @repo_1.id].to_json
      )

      IntegrationInstallationUserAssociatedRepositoriesCacheJob.perform_now(@installation)

      [@admin, @member].each do |user|
        actual_value = IntegrationInstallation::UserAssociatedRepositories.with_cache(user: user, installation: @installation) { [] }
        assert_equal [], actual_value, "cache should have been invalidated for #{user} (admin? #{@org.adminable_by?(user)})"
      end
    end
  end

  test "skips enqueue on GitHub Enterprise" do
    Flipper[:installation_user_associated_repo_ids_cache].enable(@installation.integration)
    GitHub.stubs(:enterprise?).returns(true) # rubocop:todo GitHub/DontStubEnterpriseInTests

    with_cache_enabled(/installation:user:repo_ids/) do
      assert_enqueued_jobs(0, only: IntegrationInstallationUserAssociatedRepositoriesCacheJob) do
        IntegrationInstallationUserAssociatedRepositoriesCacheJob.perform_later(@installation)
      end
    end
  end

  context "failure" do
    test "retry conditions", skip_enterprise: true do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      assert_retry_on_dirty_exit job: IntegrationInstallationUserAssociatedRepositoriesCacheJob, args: [@installation]

      assert_equal 1, GitHub.dogstats.increments("active_job.retry", tags: [
        "class:integration_installation_user_associated_repositories_cache_job",
      ]).length
    end
  end
end
