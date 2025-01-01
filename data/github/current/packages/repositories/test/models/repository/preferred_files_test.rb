# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryPreferredFilesTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @enterprise_org = create(:enterprise_linked_organization)

    @global_repo = create(:repository, owner: @user, name: Repository::GLOBAL_HEALTH_FILES_NAME)
    @enterprise_internal_global_repo = create(:internal_repository,
      owner: @enterprise_org,
      name: Repository::GLOBAL_HEALTH_FILES_NAME,
    )

    @local_repo = create(:repository, owner: @user)
    @enterprise_repo = create(:repository, owner: @enterprise_org)
    @random_repo = create(:repository)

    @local_readme = create(:repository_preferred_file, repository: @local_repo)
    @global_coc = create(:repository_preferred_file,
      filetype: :code_of_conduct,
      repository: @global_repo,
      path: "CODE_OF_CONDUCT.md",
    )
    @enterprise_internal_global_coc = create(:repository_preferred_file,
      filetype: :code_of_conduct,
      repository: @enterprise_internal_global_repo,
      path: "CODE_OF_CONDUCT.md",
    )
    @random_readme = create(:repository_preferred_file, repository: @random_repo)
    @enterprise_readme = create(:repository_preferred_file, repository: @enterprise_repo)
  end

  setup do
    @global_preferred = Repository::PreferredFiles.new(repository: @global_repo)
    @local_preferred = Repository::PreferredFiles.new(repository: @local_repo)
    @enterprise_repo_preferred = Repository::PreferredFiles.new(repository: @enterprise_repo)
  end

  context "#fetch" do
    test "returns global health files for repository without local file" do
      file = @local_preferred.fetch(:code_of_conduct)
      assert_equal :code_of_conduct, file.type
      assert_equal @global_coc, file.object
      assert_equal @local_repo, file.context_repository
    end

    test "returns local file for repository if no global files repo exists" do
      file = @local_preferred.fetch(:readme)
      assert_equal :readme, file.type
      assert_equal @local_readme, file.object
      assert_equal @local_repo, file.context_repository
    end

    test "returns local files for a repository if global files repository has no files" do
      global = create(:repository, owner: @random_repo.owner, name: Repository::GLOBAL_HEALTH_FILES_NAME)
      file = @local_preferred.fetch(:readme)
      assert_equal :readme, file.type
      assert_equal @local_readme, file.object
      assert_equal @local_repo, file.context_repository
    end

    test "returns file for global repo itself" do
      file = @global_preferred.fetch(:code_of_conduct)
      assert_equal :code_of_conduct, file.type
      assert_equal @global_coc, file.object
      assert_equal @global_repo, file.context_repository
    end

    test "local file is returned instead of global file" do
      global = create(:repository, name: Repository::GLOBAL_HEALTH_FILES_NAME)
      local = create(:repository, owner: global.owner)
      global_coc = create(:repository_preferred_file,
        filetype: :code_of_conduct,
        repository: global,
        path: "CODE_OF_CONDUCT.md",
      )
      local_coc = create(:repository_preferred_file,
        filetype: :code_of_conduct,
        repository: local,
        path: "CODE_OF_CONDUCT.md",
      )
      local_preferred = Repository::PreferredFiles.new(repository: local)
      file = local_preferred.fetch(:code_of_conduct)

      assert_equal :code_of_conduct, file.type
      assert_equal local_coc, file.object
      assert_equal local, file.context_repository
    end

    test "returns global file instead of local file if global is true" do
      global = create(:repository, name: Repository::GLOBAL_HEALTH_FILES_NAME)
      local = create(:repository, owner: global.owner)
      global_coc = create(:repository_preferred_file,
        filetype: :code_of_conduct,
        repository: global,
        path: "CODE_OF_CONDUCT.md",
      )
      local_coc = create(:repository_preferred_file,
        filetype: :code_of_conduct,
        repository: local,
        path: "CODE_OF_CONDUCT.md",
      )
      local_preferred = Repository::PreferredFiles.new(repository: local)
      file = local_preferred.fetch(:code_of_conduct, global: true)

      assert_equal :code_of_conduct, file.type
      assert_equal global_coc, file.object
      assert_equal local, file.context_repository
    end

    test "loads file type that is not cached in database" do
      repo = create(:repository, from_example: :community_files_with_legacy_issue_template)

      repo_preferred = Repository::PreferredFiles.new(repository: repo)
      file = repo_preferred.fetch(:issue_template)
      issue_template = repo.preferred_file(:issue_template)

      assert_equal :issue_template, file.type
      assert_equal issue_template, file.object
      assert_equal repo, file.context_repository
      assert_predicate file, :tree_entry?
    end

    test "loads global file type that is not cached in database when global is true" do
      repo = create(:repository, from_example: :community_files_with_legacy_issue_template)
      global_repo = create(:repository, owner: repo.owner, name: Repository::GLOBAL_HEALTH_FILES_NAME, from_example: :community_files_with_legacy_issue_template)

      repo_preferred = Repository::PreferredFiles.new(repository: repo)
      file = repo_preferred.fetch(:issue_template, global: true)
      issue_template = global_repo.preferred_file(:issue_template)

      assert_equal :issue_template, file.type
      assert_equal issue_template, file.object
      assert_equal repo, file.context_repository
      assert_predicate file, :tree_entry?
    end

    test "returns nil for file type that is not cached in database if it doesn't exist in repo" do
      assert_nil @local_preferred.fetch(:issue_template)
    end

    test "returns nil for repo without any local or global files" do
      repo = create(:repository)
      repo_preferred = Repository::PreferredFiles.new(repository: repo)
      assert_nil repo_preferred.fetch(:readme)
    end

    test "falls back to TreeEntry if cached results aren't stored" do
      tree_repo = create(:repository, from_example: :readmes)
      tree_entry = tree_repo.preferred_readme

      tree_preferred = Repository::PreferredFiles.new(repository: tree_repo)
      file = tree_preferred.fetch(:readme)
      assert_predicate file, :tree_entry?
      assert_equal :readme, file.type
      assert_equal tree_entry, file.object
      assert_equal tree_repo, file.context_repository
    end

    test "falls back to TreeEntry for blank file if cached results aren't stored" do
      tree_repo = create(:repository, from_example: :contributing_support_and_code_of_conduct)
      tree_entry = tree_repo.preferred_code_of_conduct

      tree_preferred = Repository::PreferredFiles.new(repository: tree_repo)
      file = tree_preferred.fetch(:code_of_conduct)
      assert_predicate file, :tree_entry?
      assert_equal :code_of_conduct, file.type
      assert_equal tree_entry, file.object
      assert_equal tree_repo, file.context_repository
    end

    if GitHub.enterprise?
      test "does not return global file from internal repo on GHES" do
        assert_nil @enterprise_repo_preferred.fetch(:code_of_conduct)
      end
    else
      test "does not return global file from internal repo on dotcom" do
        assert_nil @enterprise_repo_preferred.fetch(:code_of_conduct)
      end
    end
  end

  context "#exists?" do
    test "true if repo has a local preferred file type" do
      assert @local_preferred.exists?(:readme)
    end

    test "true if repo has a global preferred file type" do
      assert @local_preferred.exists?(:code_of_conduct)
    end

    test "false if repo does not have preferred file type" do
      refute @local_preferred.exists?(:contributing)
    end

    test "true if global file exists if global is true" do
      assert_equal @global_repo, @local_preferred.fetch(:code_of_conduct).repository
      assert @local_preferred.exists?(:code_of_conduct, global: true)
    end

    test "false if global file does not exist if global is true" do
      assert_equal @local_repo, @local_preferred.fetch(:readme).repository
      refute @local_preferred.exists?(:readme, global: true)
    end

    test "enqueues job to backfill for repository without records" do
      repo = create(:repository)
      repo_preferred = Repository::PreferredFiles.new(repository: repo)
      repo_preferred.exists?(:readme)
      repo_preferred.exists?(:code_of_conduct)
      repo_preferred.exists?(:contributing)

      assert_enqueued_jobs 1, only: RepositoryCheckPreferredFilesJob
    end

    test "empty repo is enqueued and updated" do
      repo = create(:repository)
      repo_preferred = Repository::PreferredFiles.new(repository: repo)

      refute repo_preferred.exists?(:readme)
      assert_empty RepositoryPreferredFile.where(repository_id: repo.id)
      assert_enqueued_jobs 1, only: RepositoryCheckPreferredFilesJob

      RepositoryCheckPreferredFilesJob.perform_now(repo.id, repo.default_oid)
      files = RepositoryPreferredFile.where(repository_id: repo.id)
      assert_equal 1, files.count
      assert_equal :no_preferred_files_found_in_repo, T.must(files.first).filetype.to_sym
    end

    test "empty repo with job already run is not enqueued" do
      repo = create(:repository)
      RepositoryCheckPreferredFilesJob.perform_now(repo.id, repo.default_oid)
      repo_preferred = Repository::PreferredFiles.new(repository: repo)
      assert_no_enqueued_jobs(only: RepositoryCheckPreferredFilesJob) do
        refute repo_preferred.exists?(:readme)
      end
      RepositoryCheckPreferredFilesJob.perform_now(repo.id, repo.default_oid)
      files = RepositoryPreferredFile.where(repository_id: repo.id)
      assert_equal 1, files.count
      assert_equal :no_preferred_files_found_in_repo, T.must(files.first).filetype.to_sym
    end

    test "enqueues a job to backfill data if committed_at is not present for local file" do
      @local_readme.update!(committed_at: nil)

      @local_preferred.exists?(:readme)
      @local_preferred.exists?(:code_of_conduct)
      @local_preferred.exists?(:contributing)

      assert_enqueued_jobs 1, only: RepositoryCheckPreferredFilesJob
    end

    test "enqueues a job to backfill data if committed_at is not present for global file" do
      @global_coc.update!(committed_at: nil)

      @local_preferred.exists?(:readme)
      @local_preferred.exists?(:code_of_conduct)
      @local_preferred.exists?(:contributing)

      assert_enqueued_jobs 1, only: RepositoryCheckPreferredFilesJob
    end

    test "does not enqueue job if files have committed_at already stored" do
      @local_preferred.exists?(:readme)
      @local_preferred.exists?(:code_of_conduct)
      @local_preferred.exists?(:contributing)

      assert_enqueued_jobs 0, only: RepositoryCheckPreferredFilesJob
    end
  end

  context "#inherited? and #async_inherited?" do
    test "true if file is only from global repo" do
      assert @local_preferred.inherited?(:code_of_conduct)
      assert @local_preferred.async_inherited?(:code_of_conduct).sync
    end

    test "false if local repo has same file type as global" do
      create(:repository_preferred_file,
        filetype: :code_of_conduct,
        repository: @local_repo,
        path: "CODE_OF_CONDUCT.md",
      )
      refute @local_preferred.inherited?(:code_of_conduct)
      refute @local_preferred.async_inherited?(:code_of_conduct).sync
    end

    test "false for file that does not exist in either local or global repo" do
      refute @local_preferred.inherited?(:contributing)
      refute @local_preferred.async_inherited?(:contributing).sync
    end

    test "false for global health files repository" do
      refute @global_preferred.inherited?(:code_of_conduct)
      refute @global_preferred.async_inherited?(:code_of_conduct).sync
    end

    test "false for repository that does not have global files repo" do
      random_repo_preferred = Repository::PreferredFiles.new(repository: @random_repo)
      refute random_repo_preferred.inherited?(:readme)
      refute random_repo_preferred.async_inherited?(:readme).sync
    end
  end
end
