# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class UpdateRepositorySponsorablesForRepositoryJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @sponsorable = create(:user, :sponsorable, login: "monalisa") # see funding_links example repo

    @repo_w_funding = create(:repository, :funding_links_enabled, from_example: :funding_links)
    RepositoryCheckPreferredFilesJob.perform_now(@repo_w_funding.id, @repo_w_funding.default_oid)

    @repo_owner_w_global_funding_file = create(:organization)
    @global_health_files_repo = create(:repository, owner: @repo_owner_w_global_funding_file,
      name: Repository::GLOBAL_HEALTH_FILES_NAME, from_example: :funding_links)
    RepositoryCheckPreferredFilesJob.perform_now(@global_health_files_repo.id, @global_health_files_repo.default_oid)

    @repo_w_global_funding = create(:repository, owner: @repo_owner_w_global_funding_file)
    RepositoryCheckPreferredFilesJob.perform_now(@repo_w_global_funding.id, @repo_w_global_funding.default_oid)

    # Create some outdated repo-sponsorable records that should get deleted when we run the job:
    @old_sponsorable = create(:user, :sponsorable)
    @outdated_repo_sponsorable = create(:repository_sponsorable, source: :repo_funding_file,
      repository: @repo_w_funding, sponsorable: @old_sponsorable)
    @outdated_global_repo_sponsorable = create(:repository_sponsorable, source: :global_funding_file,
      repository: @repo_w_global_funding, sponsorable: @old_sponsorable)
  end

  if GitHub.sponsors_enabled?
    test "creates and deletes RepositorySponsorable records to match sponsorables in repo's funding.yml" do
      assert_includes @repo_w_funding.funding_links.sponsorable_ids, @sponsorable.id
      refute_includes @repo_w_funding.funding_links.sponsorable_ids, @old_sponsorable.id

      UpdateRepositorySponsorablesForRepositoryJob.perform_now(repository_id: @repo_w_funding.id)

      assert RepositorySponsorable.exists?(@outdated_global_repo_sponsorable.id),
        "should not delete repo-sponsorable for a different repo"
      refute RepositorySponsorable.exists?(@outdated_repo_sponsorable.id),
        "should have deleted repo_funding_file repo-sponsorable for sponsorable not specified in funding file"
      new_repo_sponsorable = @repo_w_funding.repository_sponsorables.find_by(sponsorable: @sponsorable)
      refute_nil new_repo_sponsorable, "should have created repo-sponsorable for sponsorable in funding file"
      assert_predicate new_repo_sponsorable, :repo_funding_file?
    end

    test "creates and deletes RepositorySponsorable records to match sponsorables in repo owner's global funding.yml" do
      assert_includes @global_health_files_repo.funding_links.sponsorable_ids, @sponsorable.id
      refute_includes @global_health_files_repo.funding_links.sponsorable_ids, @old_sponsorable.id

      UpdateRepositorySponsorablesForRepositoryJob.perform_now(repository_id: @repo_w_global_funding.id)

      assert RepositorySponsorable.exists?(@outdated_repo_sponsorable.id),
        "should not delete repo-sponsorable for a different repo"
      refute RepositorySponsorable.exists?(@outdated_global_repo_sponsorable.id),
        "should have deleted repo_funding_file repo-sponsorable for sponsorable not specified in funding file"
      new_repo_sponsorable = @repo_w_global_funding.repository_sponsorables.find_by(sponsorable: @sponsorable)
      refute_nil new_repo_sponsorable, "should have created repo-sponsorable for sponsorable in global funding file"
      assert_predicate new_repo_sponsorable, :global_funding_file?
    end

    test "deletes global funding file repo-sponsorables when funding links disabled for repository" do
      repo = create(:repository, :funding_links_disabled, owner: @repo_owner_w_global_funding_file)

      create(:sponsors_listing, :approved, sponsorable: @repo_owner_w_global_funding_file)
      owner_repo_sponsorable = create(:repository_sponsorable, repository: repo,
        sponsorable: @repo_owner_w_global_funding_file, source: :owner)

      global_funding_link_repo_sponsorable = create(:repository_sponsorable, repository: repo,
        sponsorable: @sponsorable, source: :global_funding_file)

      UpdateRepositorySponsorablesForRepositoryJob.perform_now(repository_id: repo.id)

      assert RepositorySponsorable.exists?(owner_repo_sponsorable.id),
        "should not have deleted repo-sponsorable that's about the owner being sponsorable"
      refute RepositorySponsorable.exists?(global_funding_link_repo_sponsorable.id),
        "should have deleted global repo-sponsorable when funding links are disabled for the repository"
    end

    test "deletes repo funding file repo-sponsorables when funding links disabled for repository" do
      repo = create(:repository, :funding_links_disabled, from_example: :funding_links, owner: @sponsorable)
      create(:repository_preferred_file, :funding, repository: repo)

      owner_repo_sponsorable = create(:repository_sponsorable, repository: repo, sponsorable: @sponsorable,
        source: :owner)
      funding_link_repo_sponsorable = create(:repository_sponsorable, repository: repo, sponsorable: @sponsorable,
        source: :repo_funding_file)

      UpdateRepositorySponsorablesForRepositoryJob.perform_now(repository_id: repo.id)

      assert RepositorySponsorable.exists?(owner_repo_sponsorable.id),
        "should not have deleted repo-sponsorable that's about the owner being sponsorable"
      refute RepositorySponsorable.exists?(funding_link_repo_sponsorable.id),
        "should have deleted repo-sponsorable when funding links are disabled for the repository"
    end

    test "does not duplicate existing repo-sponsorable that is still up-to-date" do
      repo_sponsorable = create(:repository_sponsorable, source: :repo_funding_file, repository: @repo_w_funding,
        sponsorable: @sponsorable)

      UpdateRepositorySponsorablesForRepositoryJob.perform_now(repository_id: @repo_w_funding.id)

      assert RepositorySponsorable.exists?(repo_sponsorable.id)
    end

    test "retries the job on dirty exit" do
      assert_retry_on_dirty_exit(job: UpdateRepositorySponsorablesForRepositoryJob,
        args: [{ repository: @repo_w_funding }])
    end
  else
    test "no-op when Sponsors is disabled" do
      assert_no_difference(-> { RepositorySponsorable.count }) do
        UpdateRepositorySponsorablesForRepositoryJob.perform_now(repository_id: @repo_w_funding.id)
      end
    end
  end
end
