# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RepositoryCheckPreferredFilesJobTest < GitHub::TestCase
  include JobTestHelper
  include PlatformTestHelpers::InterfaceHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :simple)
    @public_repo = create(:repository, owner: @user, name: ".github", from_example: :simple)

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "add discards job without error when repo not found" do
    nonexistent_id = Repository.last.id + 100
    run_preferred_file_job_check(@repo)
  end

  test "add code of conduct presence" do
    commit_add_files ["CODE_OF_CONDUCT.md"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:code_of_conduct]
  end

  test "add codeowners presence" do
    commit_add_files ["CODEOWNERS"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:codeowners]
  end

  test "add contributing presence" do
    commit_add_files ["CONTRIBUTING.md"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:contributing]
  end

  test "add funding presence" do
    commit_add_files ["FUNDING.yml"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:funding]
  end

  test "enqueues job to update repo-sponsorables when adding funding file" do
    commit_add_files ["FUNDING.yml"]
    assert_enqueued_with(
      job: UpdateRepositorySponsorablesForRepositoryJob,
      args: [{ repository_id: @repo.id }],
    ) do
      run_preferred_file_job_check(@repo)
    end
  end if GitHub.sponsors_enabled?

  test "does not enqueue job to update repo-sponsorables when adding non-funding file" do
    commit_add_files ["README.md"]
    assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForRepositoryJob) do
      run_preferred_file_job_check(@repo)
    end
  end if GitHub.sponsors_enabled?

  test "test lock works properly" do
    # We have a lock for the same params
    assert_enqueued_jobs(1, only: RepositoryCheckPreferredFilesJob) do
      RepositoryCheckPreferredFilesJob.perform_later(1, "random_oid")
      RepositoryCheckPreferredFilesJob.perform_later(1, "random_oid")
      RepositoryCheckPreferredFilesJob.perform_later(1, "random_oid")
    end
  end

  test "test lock works properly with different second param" do
    assert_enqueued_jobs(3, only: RepositoryCheckPreferredFilesJob) do
      RepositoryCheckPreferredFilesJob.perform_later(1, "random_oid")
      RepositoryCheckPreferredFilesJob.perform_later(1, "random_oid2")
      RepositoryCheckPreferredFilesJob.perform_later(1, "random_oid3")
    end
  end

  test "test lock works properly with different first param" do
    assert_enqueued_jobs(3, only: RepositoryCheckPreferredFilesJob) do
      RepositoryCheckPreferredFilesJob.perform_later(1, "random_oid")
      RepositoryCheckPreferredFilesJob.perform_later(2, "random_oid")
      RepositoryCheckPreferredFilesJob.perform_later(3, "random_oid")
    end
  end

  test "test lock works properly with same params after an hour" do
    assert_enqueued_jobs(2, only: RepositoryCheckPreferredFilesJob) do
      RepositoryCheckPreferredFilesJob.perform_later(1, "random_oid")
      Timecop.travel(2.hours.from_now) do
        RepositoryCheckPreferredFilesJob.perform_later(1, "random_oid")
        RepositoryCheckPreferredFilesJob.perform_later(1, "random_oid")
      end
    end
  end

  test "add readme presence" do
    commit_add_files ["README.md"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:readme]
  end

  test "add readme presence MT" do
    on_multi_tenant_enterprise do
      user = create(:emu)
      GitHub::CurrentTenant.set(user.enterprise_managed_business)
      repo = create(:repository, owner: user, from_example: :simple)
      commit_add_files(["README.md"], repo: repo)

      # Simulate no tenant being set
      GitHub::CurrentTenant.remove
      assert_nil GitHub::CurrentTenant.get
      refute_predicate GitHub::CurrentTenant, :unscoped?
      refute repo.reload.owner

      run_preferred_file_job_check(repo)
      assert_preferred_files([:readme], repo: repo)
      # The job should have resolved and set tenant
      assert user.enterprise_managed_business, GitHub::CurrentTenant.get
    end
  end

  test "add support presence" do
    commit_add_files ["SUPPORT.md"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:support]
  end

  test "add license presence" do
    commit_add_files ["LICENSE.md"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:license]
  end

  test "add security policy presence" do
    commit_add_files ["SECURITY.md"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:security]
  end

  test "remove security policy presence" do
    commit_add_files ["SECURITY.md"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:security]

    commit_remove_files ["SECURITY.md"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:no_preferred_files_found_in_repo]
  end

  test "enqueues job to update repo-sponsorables when removing funding file" do
    commit_add_files ["FUNDING.yml"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:funding]

    commit_remove_files ["FUNDING.yml"]
    assert_enqueued_with(
      job: UpdateRepositorySponsorablesForRepositoryJob,
      args: [{ repository_id: @repo.id }],
    ) do
      run_preferred_file_job_check(@repo)
    end
  end if GitHub.sponsors_enabled?

  test "does not enqueue job to update repo-sponsorables when non-funding file is removed" do
    commit_add_files ["README.md"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:readme]

    commit_remove_files ["README.md"]
    assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForRepositoryJob) do
      run_preferred_file_job_check(@repo)
    end
  end if GitHub.sponsors_enabled?

  test "enqueues job to update repo-sponsorables for repositories inheriting from global health files repo that gets a funding file" do
    repo_owner = create(:organization)
    global_health_files_repo = create(:repository, owner: repo_owner, name: Repository::GLOBAL_HEALTH_FILES_NAME,
      from_example: :simple)
    commit_add_files ["FUNDING.yml"], repo: global_health_files_repo

    assert_enqueued_with(
      job: UpdateRepositorySponsorablesForGlobalRepoJob,
      args: [{ repository_id: global_health_files_repo.id }],
    ) do
      run_preferred_file_job_check(global_health_files_repo)
    end

    assert_preferred_files [:funding], repo: global_health_files_repo
  end if GitHub.sponsors_enabled?

  test "does not enqueue job to update repo-sponsorables for repositories inheriting from global health files repo that gets a non-funding file" do
    repo_owner = create(:organization)
    global_health_files_repo = create(:repository, owner: repo_owner, name: Repository::GLOBAL_HEALTH_FILES_NAME,
      from_example: :simple)
    commit_add_files ["README.md"], repo: global_health_files_repo

    assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForGlobalRepoJob) do
      run_preferred_file_job_check(global_health_files_repo)
    end

    assert_preferred_files [:readme], repo: global_health_files_repo
  end if GitHub.sponsors_enabled?

  test "updates empty on first backfill" do
    assert_preferred_files []
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:no_preferred_files_found_in_repo]
  end

  test "updates empty on first backfill even on nil default_oid" do
    repo = create(:repository, from_example: :simple)
    assert_preferred_files []
    run_preferred_file_job_check(repo)
    files = RepositoryPreferredFile.where(repository: repo).pluck(:filetype)
    assert_equal 1, files.length
    assert_equal :no_preferred_files_found_in_repo, files.first.to_sym

    commit_add_files(["SECURITY.md"], repo: repo)
    run_preferred_file_job_check(repo)
    files = RepositoryPreferredFile.where(repository: repo).pluck(:filetype)
    assert_equal 1, files.length
    assert_equal :security, files.first.to_sym
  end

  test "wipes empty status when a real file is added" do
    assert_preferred_files []
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:no_preferred_files_found_in_repo]

    commit_add_files ["SECURITY.md"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:security]

    commit_remove_files ["SECURITY.md"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:no_preferred_files_found_in_repo]
  end

  test "ignore file from .github repo" do
    commit_add_files ["SECURITY.md"], repo: @public_repo
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:no_preferred_files_found_in_repo]
  end

  test "prefer local file instead of .github repo" do
    commit = commit_add_files ["SECURITY.md"], repo: @repo
    commit_add_files ["SECURITY.md"], repo: @public_repo
    run_preferred_file_job_check(@repo)
    preferred_files = RepositoryPreferredFile.where(repository: @repo)
    assert_equal commit.oid, preferred_files.first.commit_oid
  end

  test "multiple files" do
    commit_add_files ["CODE_OF_CONDUCT.md", "SECURITY.md", "LICENSE.md"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:code_of_conduct, :security, :license]
  end

  test "funding presence in a subfolder" do
    commit_add_files [".github/FUNDING.yml"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:funding]
  end

  test "enqueues job to update repo-sponsorables when adding funding file to a subfolder" do
    commit_add_files [".github/FUNDING.yml"]
    assert_enqueued_with(
      job: UpdateRepositorySponsorablesForRepositoryJob,
      args: [{ repository_id: @repo.id }],
    ) do
      run_preferred_file_job_check(@repo)
    end
  end if GitHub.sponsors_enabled?

  test "does not enqueue job to update repo-sponsorables when adding non-funding file to a subfolder" do
    commit_add_files [".github/README.md"]
    assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForRepositoryJob) do
      run_preferred_file_job_check(@repo)
    end
  end if GitHub.sponsors_enabled?

  test "detects two new files" do
    commit_add_files ["CODE_OF_CONDUCT.md"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:code_of_conduct]

    commit_add_files ["SECURITY.md"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:code_of_conduct, :security]

    commit_add_files ["LICENSE.md"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:code_of_conduct, :security, :license]
  end

  test "enqueues job to update repo-sponsorables when updating a funding file" do
    sponsorable1, sponsorable2 = create_pair(:user, :sponsorable)
    commit_add_files ["FUNDING.yml"], content: "github: #{sponsorable1}"
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:funding]

    commit_add_files ["FUNDING.yml"], content: "github: #{sponsorable2}"
    assert_enqueued_with(
      job: UpdateRepositorySponsorablesForRepositoryJob,
      args: [{ repository_id: @repo.id }],
    ) do
      run_preferred_file_job_check(@repo)
    end
    assert_preferred_files [:funding]
  end if GitHub.sponsors_enabled?

  test "does not enqueue job to update repo-sponsorables when updating a non-funding file" do
    commit_add_files ["README.md"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:readme]

    commit_add_files ["README.md"]
    assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForRepositoryJob) do
      run_preferred_file_job_check(@repo)
    end
    assert_preferred_files [:readme]
  end if GitHub.sponsors_enabled?

  test "does not enqueue job to update repo-sponsorables when updating a non-funding file and repo has a funding file" do
    sponsorable = create(:user, :sponsorable)

    # Should enqueue job for repo-sponsorables when first adding a funding file:
    commit_add_files ["FUNDING.yml", "README.md"], content: "github: #{sponsorable}\n"
    assert_enqueued_with(
      job: UpdateRepositorySponsorablesForRepositoryJob,
      args: [{ repository_id: @repo.id }],
    ) do
      run_preferred_file_job_check(@repo)
    end
    assert_preferred_files [:funding, :readme]

    # Should not enqueue job for repo-sponsorables when we update a non-funding file in the same repo:
    commit_add_files ["README.md"]
    assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForRepositoryJob) do
      run_preferred_file_job_check(@repo)
    end
    assert_preferred_files [:funding, :readme]
  end if GitHub.sponsors_enabled?

  test "update commit oid and paths" do
    commit = commit_add_files [".github/FUNDING.yml"]
    run_preferred_file_job_check(@repo)
    preferred_files = RepositoryPreferredFile.where(repository: @repo)
    assert_equal commit.oid, preferred_files.first.commit_oid
    assert_equal ".github/FUNDING.yml", preferred_files.first.path

    commit = @repo.refs.find("master").append_commit({ message: "Rename path", author: @user }, @user) do |files|
      files.remove ".github/FUNDING.yml"
      files.add "FUNDING.yml", "Rename"
    end

    run_preferred_file_job_check(@repo)
    preferred_files = RepositoryPreferredFile.where(repository: @repo)
    assert_equal 1, preferred_files.size
    assert_equal commit.oid, preferred_files.first.commit_oid
    assert_equal "FUNDING.yml", preferred_files.first.path
  end

  test "path and commit oid" do
    commit = commit_add_files([".github/FUNDING.yml"])
    run_preferred_file_job_check(@repo)
    preferred_files = RepositoryPreferredFile.where(repository: @repo)
    assert_equal 1, preferred_files.size
    preferred_file = preferred_files.first
    assert_equal ".github/FUNDING.yml", preferred_files.first.path
    assert_equal commit.oid, preferred_files.first.commit_oid
  end

  test "test content update updates the commit oid" do
    commit = commit_add_files([".github/FUNDING.yml"], content: "First content")
    run_preferred_file_job_check(@repo)
    preferred_files = RepositoryPreferredFile.where(repository: @repo)
    assert_equal 1, preferred_files.size
    preferred_file = preferred_files.first

    commit_two = commit_add_files([".github/FUNDING.yml"], content: "Fixed some random typo")
    run_preferred_file_job_check(@repo)
    preferred_files_two = RepositoryPreferredFile.where(repository: @repo)

    assert_equal ".github/FUNDING.yml", preferred_files.first.path
    assert_equal commit.oid, preferred_files.first.commit_oid

    assert_equal ".github/FUNDING.yml", preferred_files_two.first.path
    assert_equal commit_two.oid, preferred_files_two.first.commit_oid
  end

  test "stores committed_at for files" do
    travel_to "2023-11-13"
    committed_at = 3.days.ago

    travel_to(committed_at) do
      commit = commit_add_files([".github/FUNDING.yml"], content: "First content")
      run_preferred_file_job_check(@repo)

      file = RepositoryPreferredFile.find_by(repository: @repo, filetype: :funding)
      assert_equal committed_at.to_i, file.committed_at.to_i
    end
  end

  test "sets has_content to true if file has content" do
    commit = commit_add_files([".github/FUNDING.yml"], content: "First content")
    run_preferred_file_job_check(@repo)

    file = RepositoryPreferredFile.find_by(repository: @repo, filetype: :funding)
    assert_predicate file, :has_content?
  end

  test "sets has_content to false if file is blank" do
    commit = commit_add_files([".github/FUNDING.yml"], content: "\n")
    run_preferred_file_job_check(@repo)

    file = RepositoryPreferredFile.find_by(repository: @repo, filetype: :funding)
    refute_predicate file, :has_content?
  end

  test "runs no changing queries when no update is needed" do
    commit = commit_add_files([".github/FUNDING.yml"], content: "\n")
    run_preferred_file_job_check(@repo)

    _, queries = log_queries do
      run_preferred_file_job_check(@repo)
    end

    queries.map(&:digested_sql).each do |query|
      assert query.start_with?("SELECT")
    end
  end

  test "runs only UPDATE when no new rows are inserted" do
    commit = commit_add_files [".github/FUNDING.yml"]
    run_preferred_file_job_check(@repo)

    commit = @repo.refs.find("master").append_commit({ message: "Rename path", author: @user }, @user) do |files|
      files.remove ".github/FUNDING.yml"
      files.add "FUNDING.yml", "Rename"
    end
    _, queries = log_queries do
      run_preferred_file_job_check(@repo)
    end

    queries.map(&:sql).each do |query|
      refute query.start_with?("INSERT")
    end
  end

  test "handles GitRPC::ObjectMissing" do
    Repository.any_instance.stubs(:ref_to_sha).raises(GitRPC::ObjectMissing.new)

    commit_add_files ["CODE_OF_CONDUCT.md"]
    run_preferred_file_job_check(@repo)
    assert_preferred_files [:no_preferred_files_found_in_repo]
  end

  def run_preferred_file_job_check(repo)
    RepositoryCheckPreferredFilesJob.perform_now(repo.id, repo.default_oid)
  end

  def commit_add_files(filenames, repo: @repo, content: "Content")
    repo.refs.find("master").append_commit({ message: "Add files", author: @user }, @user) do |files|
      filenames.each do |filename|
        files.add filename, content
      end
    end
  end

  def commit_remove_files(filenames, repo = @repo)
    repo.refs.find("master").append_commit({ message: "Remove files", committer: @user }, @user) do |files|
      filenames.each do |filename|
        files.remove filename
      end
    end
  end

  def assert_preferred_files(enabled_types, repo: @repo)
    preferred_files = RepositoryPreferredFile.where(repository: repo).pluck(:filetype)

    assert_equal enabled_types.length, preferred_files.length
    enabled_types.each do |type|
      assert preferred_files.include? type.to_s
    end
  end
end
