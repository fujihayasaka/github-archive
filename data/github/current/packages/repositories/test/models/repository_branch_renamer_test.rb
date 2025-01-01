# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class RepositoryBranchRenamerTest < GitHub::TestCase
  include HydroTestHelpers
  include PageHelper
  include PullRequestSynchronizationTestHelpers

  fixtures do
    @user = create(:user, login: "owner", plan: "pro")
    @repo = create(:repository, owner: @user, from_example: :simple)
    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  context "#for_starting_rename_process" do
    test "returns a RepositoryBranchRenamer for the specified branch" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
      assert_equal "master", renamer.old_name
      assert_equal @repo, renamer.repository
      assert_nil renamer.error
      assert_nil renamer.rename
    end
  end

  context "#start_rename" do
    test "creates RepositoryBranchRename record" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")

      assert_difference(-> { RepositoryBranchRename.count }) do
        result = renamer.start_rename("main", actor: @user, entry_point: :test_case)
        assert_nil renamer.error
        assert result
      end

      rename = T.must(renamer.rename).reload
      refute_nil rename
      assert_equal @repo, rename.repository
      assert_equal @user, rename.user
      assert_equal "cr-line-endings", rename.old_name
      assert_equal "main", rename.new_name
      assert_predicate rename, :started?
      refute_predicate rename, :default_branch?
    end

    test "sets error when given a nil branch name" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")

      refute renamer.start_rename(nil, actor: @user, entry_point: :test_case)

      assert_equal :invalid_new_name, renamer.error
      assert_equal "not a valid name for a branch", renamer.human_error
    end

    test "sets error when given an invalid new branch name" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")

      refute renamer.start_rename(" --", actor: @user, entry_point: :test_case)

      assert_equal :invalid_new_name, renamer.error
      assert_equal "not a valid name for a branch", renamer.human_error
    end

    test "sets error when given a branch name starting with refs/heads" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "refs/heads/test")

      refute renamer.start_rename("temp", actor: @user, entry_point: :test_case)

      assert_equal :invalid_old_name, renamer.error
      assert_equal "branch must be deleted and recreated", renamer.human_error
    end

    test "sets error when new branch creation fails due to invalid branch name" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      Git::Ref::Collection.any_instance.stubs(:create).raises(Git::Ref::InvalidName)

      refute renamer.start_rename("pickles", actor: @user, entry_point: :test_case)

      assert_predicate T.must(renamer.rename).reload, :new_branch_invalid_name?
      assert_equal "new_branch_invalid_name", T.must(renamer.rename).error_reason
      assert_equal "'pickles' is not a valid branch name", T.must(renamer.rename).human_error_reason
    end

    test "sets error when new branch creation fails due to branch already existing" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      Git::Ref::Collection.any_instance.stubs(:create).raises(Git::Ref::ExistsError)

      refute renamer.start_rename("pickles", actor: @user, entry_point: :test_case)

      assert_predicate T.must(renamer.rename).reload, :new_branch_already_exists?
      assert_equal "new_branch_already_exists", T.must(renamer.rename).error_reason
      assert_equal "branch pickles already exists", T.must(renamer.rename).human_error_reason
    end

    test "sets error when new branch creation fails due to hook failure" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      Git::Ref::Collection.any_instance.stubs(:create).raises(Git::Ref::HookFailed)

      refute renamer.start_rename("pickles", actor: @user, entry_point: :test_case)

      assert_predicate T.must(renamer.rename).reload, :new_branch_hook_failure?
      assert_equal "new_branch_hook_failure", T.must(renamer.rename).error_reason
      assert_equal "could not create branch pickles", T.must(renamer.rename).human_error_reason
    end

    test "sets error when git can't be reached on new branch creation" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      Git::Ref.any_instance.stubs(:write_ref).raises(GitHub::DGit::ThreepcFailedToLock)

      refute renamer.start_rename("pickles", actor: @user, entry_point: :test_case)

      assert_predicate T.must(renamer.rename).reload, :new_branch_dgit_error?
      assert_equal :new_branch_dgit_error, renamer.error
      assert_equal "could not create branch pickles", renamer.human_error
    end

    test "records latest commit SHA of old branch" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      latest_commit = @repo.ref_to_sha("cr-line-endings")
      refute_nil latest_commit, "expected cr-line-endings branch to have a commit"

      assert renamer.start_rename("main", actor: @user, entry_point: :test_case)

      refute_nil renamer.rename
      assert_equal latest_commit, T.must(renamer.rename).reload.old_sha
    end

    test "creates branch with new name" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert_nil @repo.heads.find("main"),
        "expect new branch not to exist before doing the rename"

      assert renamer.start_rename("main", actor: @user, entry_point: :test_case)

      refute_nil @repo.heads.find("main"),
        "expect new branch to exist after the rename"
    end

    test "new branch has the same commits as old branch" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      old_branch_commits = get_commits("cr-line-endings")
      refute_empty old_branch_commits, "expected old branch to have some commits"

      assert renamer.start_rename("main", actor: @user, entry_point: :test_case)

      new_branch_commits = get_commits("main")
      assert_equal old_branch_commits, new_branch_commits
    end

    test "updates default branch" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
      assert_equal "master", @repo.default_branch,
        "expected old branch to be repo's current default branch"

      assert renamer.start_rename("main", actor: @user, entry_point: :test_case)

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_equal "main", @repo.reload.default_branch
      assert_predicate T.must(renamer.rename).reload, :default_branch?
    end

    test "sets error when git can't be reached on update default branch" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
      Repository.any_instance.stubs(:update_default_branch_spokes).raises(GitHub::DGit::ThreepcFailedToLock)

      renamer.start_rename("main", actor: @user, entry_point: :test_case)

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :update_default_branch_dgit_error?
      assert_equal "update_default_branch_dgit_error", T.must(renamer.rename).error_reason
      assert_equal "could not change default branch of #{@repo.nwo}", T.must(renamer.rename).human_error_reason
    end

    test "sets error when update default branch times out" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
      Repository.any_instance.stubs(:update_default_branch_spokes).raises(GitRPC::Timeout)

      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :update_default_branch_gitrpc_timeout?
      assert_equal "update_default_branch_gitrpc_timeout", T.must(renamer.rename).error_reason
      assert_equal "could not change default branch of #{@repo.nwo}", T.must(renamer.rename).human_error_reason
    end

    test "returns true when rename to given new branch has already been started" do
      rename = create(:repository_branch_rename, repository: @repo,
        old_name: "master", new_name: "main")

      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")

      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"
    end

    test "sets error when old branch has no commits" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
      Repository.any_instance.stubs(:ref_to_sha).returns(nil)

      assert_no_difference(-> { RepositoryBranchRename.count }) do
        refute renamer.start_rename("main", actor: @user, entry_point: :test_case)
      end

      assert_equal :old_branch_has_no_commit, renamer.error
      assert_equal "branch master has no commits", renamer.human_error
    end

    test "sets error when couldn't update default branch" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
      Repository.any_instance.stubs(:point_to_new_default_branch).returns(false)

      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :failed_to_update_default_branch?
      assert_equal "failed_to_update_default_branch", T.must(renamer.rename).error_reason
      assert_equal "could not change default branch of #{@repo.nwo}", T.must(renamer.rename).human_error_reason
    end

    test "sets error when repository rules are violated" do
      ruleset = create(:repository_ruleset, source: @repo)
      create(:repository_rule_condition, :targets_branch, branch_name: "refs/heads/develop", repository_ruleset: ruleset)
      create(:repository_rule_configuration, rule_type: "creation", repository_ruleset: ruleset)

      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
      renamer.start_rename("develop", actor: @user, entry_point: :test_case)

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :repository_rule_violation?
      assert_equal :repository_rule_violation, renamer.error
      assert_equal "repository rules do not permit renaming branch 'master' to 'develop'", renamer.human_error
    end

    test "sets error when #start_rename fails unexpectedly" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      Git::Ref::Collection.any_instance.stubs(:create).raises(StandardError)

      refute renamer.start_rename("pickles", actor: @user, entry_point: :test_case)

      assert_predicate T.must(renamer.rename).reload, :start_rename_failed?
      assert_equal :start_rename_failed, renamer.error
      assert_equal "could not start renaming branch 'cr-line-endings' to 'pickles'", renamer.human_error
    end

    test "leaves the rename record as started" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")

      assert renamer.start_rename("main", actor: @user, entry_point: :test_case)
      assert_predicate T.must(renamer.rename).reload, :started?
    end

    test "cannot create a branch with a name length of 300 bytes" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
      refute renamer.start_rename("z" * 300, actor: @user, entry_point: :test_case)
      assert_equal "Sorry, refs longer than 255 bytes are not allowed.", renamer.human_error
    end

    test "cannot create a branch with a name length of 256 bytes" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
      refute renamer.start_rename("z" * 256, actor: @user, entry_point: :test_case)
      assert_equal "Sorry, refs longer than 255 bytes are not allowed.", renamer.human_error
    end

    test "cannot create a branch with a name length of 250 bytes" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
      refute renamer.start_rename("z" * 250, actor: @user, entry_point: :test_case)
      assert_equal "Sorry, refs longer than 255 bytes are not allowed.", renamer.human_error
    end

    test "can create a branch with a name length of 240 bytes" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
      assert renamer.start_rename("z" * 240, actor: @user, entry_point: :test_case)
    end
  end

  context "#finish_rename" do
    test "returns true when rename already finished 2" do
      orchestration = start_pause_and_resume_rename(repository: @repo, old_name: "master", new_name: "main") do |o|
        o.rename.update!(state: :finished)
      end

      assert_equal :skipped, orchestration.reload.state.to_sym
    end

    test "returns false when rename is in error state 2" do
      orchestration = start_pause_and_resume_rename(repository: @repo, old_name: "master", new_name: "main", raises: false) do |o|
        o.rename.update!(state: :errored)
      end

      assert_equal :failed, orchestration.reload.state.to_sym
    end

    test "does not update Pages branch when an unrelated branch is being renamed" do
      page = create :page, example_repo: :pages_gh_pages_only, owner: @user
      repo = page.repository
      assert_equal "gh-pages", page.source_branch
      assert_equal "/", page.source_dir
      assert_equal "gh-pages", repo.pages_branch,
        "need to make sure the Pages branch is not the one we're renaming"

      # Commit to the branch we're renaming so the rename can start successfully:
      pages_ref = repo.heads.find("gh-pages")
      refute_nil pages_ref, "repo should have gh-pages branch"
      ref = repo.heads.create("master", pages_ref.target, @user)
      commit_meta = { message: "some changes", committer: @user }
      ref.append_commit(commit_meta, @user) { |files| files.add("file001", "foo") }

      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: repo, branch_name: "master")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_nil T.must(renamer.rename).reload.error_reason
      assert_equal "gh-pages", repo.reload.pages_branch, "Pages branch should not have changed"
      assert_equal "gh-pages", page.reload.source_branch, "Pages source should not have changed"
      assert_equal "/", page.source_dir, "default source directory should not have changed"
    end

    test "updates Pages branch when it's being renamed" do
      page = create :page, example_repo: :pages_gh_pages_only, owner: @user
      repo = page.repository
      assert_equal "gh-pages", page.source_branch
      assert_equal "/", page.source_dir
      assert_equal "gh-pages", repo.pages_branch,
        "need to make sure the Pages branch is the one we're renaming"
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: repo, branch_name: "gh-pages")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_nil T.must(renamer.rename).reload.error_reason
      assert_equal "main", repo.reload.pages_branch
      assert_equal "main", page.reload.source_branch
      assert_equal "/", page.source_dir, "default source directory should not have changed"
    end

    test "preserves Pages subdirectory when Pages branch is being renamed" do
      page = create :page, example_repo: :pages_master_only, owner: @user, source: "master"
      repo = page.repository
      page.set_source(ref_name: "master", subdir: "/docs")
      assert_equal "master", page.source_branch
      assert_equal "master", repo.pages_branch,
        "need to make sure the Pages branch is the one we're renaming"
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: repo, branch_name: "master")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_nil T.must(renamer.rename).reload.error_reason
      assert_equal "main", repo.reload.pages_branch
      assert_equal "main", page.reload.source_branch
      assert_equal "/docs", page.source_dir
    end

    test "updates base branch of open pull request in the repo when base branch is renamed" do
      pull = create(:pull_request, repository: @repo, base_ref: "master",
        head_ref: "cr-line-endings")
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_nil T.must(renamer.rename).reload.error_reason
      assert_equal "main", pull.reload.base_ref
      assert_equal "cr-line-endings", pull.head_ref, "head ref should not have changed"
      ref = @repo.heads.find("master")
      assert_nil ref, "branch should have been deleted since retargeting PRs succeeded"
    end

    test "does not update pull request head ref when head branch is renamed" do
      pull = create(:pull_request, repository: @repo, base_ref: "master",
        head_ref: "cr-line-endings")
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("new-name", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"

      with_hydro_pr_jobs do
        perform_enqueued_jobs(only: [RepositoryOrchestrationJob])
      end

      assert_nil T.must(renamer.rename).reload.error_reason
      assert_equal "cr-line-endings", pull.reload.head_ref, "head ref should not have changed"
      assert_equal "master", pull.base_ref, "base ref should not have changed"
      assert_predicate pull, :closed?, "should have closed pull request"
    end

    test "does not set error when pull request retarget fails" do
      pull = create(:pull_request, repository: @repo, base_ref: "master",
        head_ref: "cr-line-endings")
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"
      PullRequest.any_instance.expects(:rename_base_branch).
        raises(ActiveRecord::ActiveRecordError.new(nil))

      assert_difference(-> { renamer.failed_pr_retarget_count }) do
        perform_enqueued_jobs(only: [RepositoryOrchestrationJob])
      end

      rename = T.must(renamer.rename).reload
      refute_nil rename
      assert_predicate rename, :finished?
      assert_predicate rename, :pull_request_retarget_failed?,
        "should still mark error_reason to be able to notify the user later"
      assert_equal "cr-line-endings", pull.reload.head_ref, "head ref should not have changed"
      assert_equal "master", pull.base_ref, "base ref should not have changed"
      assert_predicate pull, :open?, "PR state should not have changed"
      ref = @repo.heads.find("master")
      refute_nil ref, "branch should not have been deleted as part of rename " \
        "process since PR retargeting did not succeed"
    end

    test "does not update base branch of open pull request whose head repo is the one with the branch" do
      forking_user = create(:user)
      fork, status = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @repo.fork(forker: forking_user)
      end
      assert_equal :created, status, "fork should have been created"

      ref = @repo.heads.find("master")
      refute_nil ref, "repo should have master branch"
      commit_meta = { message: "some changes", committer: @user }
      ref.append_commit(commit_meta, @user) { |files| files.add("file001", "foo") }

      pull = create(:pull_request,
        issue: create(:issue, repository: fork),
        base_repository: fork,
        base_ref: "master",
        base_user: forking_user,
        head_repository: @repo,
        head_ref: "master",
        head_user: @user)

      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert T.must(renamer.rename).reload.finished?
      refute T.must(renamer.rename).human_error_reason
      assert_equal "master", pull.reload.base_ref, "base ref should not have changed"
      assert_equal "master", pull.head_ref, "head ref should not have changed"
      assert_equal fork, pull.base_repository, "base repo should not have changed"
      assert_equal forking_user, pull.base_user, "base user should not have changed"
      assert_equal @repo, pull.head_repository, "head repo should not have changed"
      assert_equal @user, pull.head_user, "head user should not have changed"
      assert_predicate pull, :open?, "PR state should not have changed"
    end

    test "does not update base branch of open pull request from spammy fork" do
      forking_user = create(:user, login: "spammy-forker")
      fork, status = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @repo.fork(forker: forking_user)
      end
      assert_equal :created, status, "fork should have been created"

      ref = fork.heads.find("master")
      refute_nil ref, "fork should have master branch"
      commit_meta = { message: "some changes", committer: forking_user }
      ref.append_commit(commit_meta, forking_user) { |files| files.add("file001", "foo") }

      pull = create(:pull_request,
        issue: create(:issue, repository: @repo),
        base_repository: @repo,
        base_ref: "master",
        base_user: @user,
        head_repository: fork,
        head_ref: "master",
        head_user: forking_user)

      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) { forking_user.mark_as_spammy }
      assert_predicate fork.reload, :spammy?, "fork should now be spammy"

      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected first rename process to start successfully"

      with_hydro_pr_jobs do
        perform_enqueued_jobs(only: [RepositoryOrchestrationJob])
      end

      assert_nil T.must(renamer.rename).reload.error_reason
      assert_equal "master", pull.reload.base_ref, "base ref should not have changed"
      assert_equal "master", pull.head_ref, "head ref should not have changed"
      assert_equal @repo, pull.base_repository, "base repo should not have changed"
      assert_equal @user, pull.base_user, "base user should not have changed"
      assert_equal fork, pull.head_repository, "head repo should not have changed"
      assert_equal forking_user, pull.head_user, "head user should not have changed"
      assert_predicate pull, :closed?, "PR should have been closed once branch was renamed"
    end if GitHub.spamminess_check_enabled?

    test "updates base branch of open pull request from fork when base branch is renamed" do
      forking_user = create(:user, login: "forker")
      fork, status = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @repo.fork(forker: forking_user)
      end
      assert_equal :created, status, "fork should have been created"

      ref = fork.heads.find("master")
      refute_nil ref, "fork should have master branch"
      commit_meta = { message: "some changes", committer: forking_user }
      ref.append_commit(commit_meta, forking_user) { |files| files.add("file001", "foo") }

      pull = create(:pull_request,
        issue: create(:issue, repository: @repo),
        base_repository: @repo,
        base_ref: "master",
        base_user: @user,
        head_repository: fork,
        head_ref: "master",
        head_user: forking_user)

      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected first rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_nil T.must(renamer.rename).reload.error_reason
      assert_equal "main", pull.reload.base_ref
      assert_equal "master", pull.head_ref, "head ref should not have changed"
      assert_equal @repo, pull.base_repository, "base repo should not have changed"
      assert_equal @user, pull.base_user, "base user should not have changed"
      assert_equal fork, pull.head_repository, "head repo should not have changed"
      assert_equal forking_user, pull.head_user, "head user should not have changed"
    end

    test "does not finish rename if new branch name exists among old branch names" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected first rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      second_renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo.reload, branch_name: "main")
      assert second_renamer.start_rename("master", actor: @user, entry_point: :test_case),
        "expected second rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(second_renamer.rename).reload, :finished?
      assert_predicate T.must(renamer.rename).reload, :moot?
    end

    test "updates target of draft release for non-default branch" do
      release = create(:release, repository: @repo, target_commitish: "cr-line-endings",
        state: :draft)
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_equal "main", release.reload.target_commitish
    end

    test "updates target of draft release for default branch" do
      release = create(:release, repository: @repo, target_commitish: nil, state: :draft)
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
      assert_equal "master", @repo.default_branch, "expected 'master' to be default branch"
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_equal "main", release.reload.target_commitish
    end

    test "does not update target of published release" do
      release = create(:release, :published, repository: @repo,
        target_commitish: "cr-line-endings")
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_equal "cr-line-endings", release.reload.target_commitish
    end

    test "deletes old branch" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"
      refute_nil @repo.heads.find("cr-line-endings"),
        "expect old branch to exist before finishing the rename"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_nil @repo.reload.heads.find("cr-line-endings"),
        "expect old branch to no longer exist after the rename"
    end

    test "sets error when old branch cannot be deleted" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"
      Git::Ref.any_instance.stubs(:deleteable_to_complete_rename?).returns(false)

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :old_branch_not_deletable?
      assert_equal "old_branch_not_deletable", T.must(renamer.rename).error_reason
      assert_equal "branch cr-line-endings cannot be deleted", T.must(renamer.rename).human_error_reason
    end

    test "sets error when deletion of old branch fails" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"
      Git::Ref.any_instance.stubs(:delete).raises(Git::Ref::HookFailed)

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :old_branch_hook_failure?
      assert_equal "old_branch_hook_failure", T.must(renamer.rename).error_reason
      assert_equal "could not delete branch cr-line-endings", T.must(renamer.rename).human_error_reason
    end

    test "instruments an audit log event for repo.rename_branch" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"
      expected_payload = {
        # Latest commit in cr-line-endings branch:
        old_sha: "e91a032dc9f19058a375fb3db68c9dda73527d13",
        old_branch: "cr-line-endings",
        new_branch: "main",
        default_branch: false,
        repo: @repo.nwo,
        repo_id: @repo.id,
        actor: @user.login,
        actor_id: @user.id,
        user: @user.login,
        user_id: @user.id,
      }
      events = subscribe("repo.rename_branch")

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert event = events.pop, "expected an event to be instrumented"
      assert_subset_hash expected_payload, event.payload
    end

    test "updates rename record's state" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"
      assert_predicate renamer.rename, :started?, "rename record should still be 'started'"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :finished?, "rename record should now be 'finished'"
    end

    test "sets error when old branch git can't be reached" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"
      Git::Ref.any_instance.stubs(:delete).raises(GitHub::DGit::ThreepcFailedToLock)

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :old_branch_dgit_error?
      assert_equal "old_branch_dgit_error", T.must(renamer.rename).error_reason
      assert_equal "could not delete branch cr-line-endings", T.must(renamer.rename).human_error_reason
    end

    test "sets error when repository is archived" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"
      @repo.set_archived

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :unwritable_repository?
      assert_equal "unwritable_repository", T.must(renamer.rename).error_reason
      assert_equal "#{@repo.nwo} is archived, migrating, or disabled", T.must(renamer.rename).human_error_reason
    end

    test "sets error when repository is locked for migration" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"
      @repo.lock_for_migration

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :unwritable_repository?
      assert_equal "unwritable_repository", T.must(renamer.rename).error_reason
      assert_equal "#{@repo.nwo} is archived, migrating, or disabled", T.must(renamer.rename).human_error_reason
    end

    test "sets error when repository is disabled" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
        "expected rename process to start successfully"
      @repo.access.disable("size", create(:staff_admin_user))

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :unwritable_repository?
      assert_equal "unwritable_repository", T.must(renamer.rename).error_reason
      assert_equal "#{@repo.nwo} is archived, migrating, or disabled", T.must(renamer.rename).human_error_reason
    end

    test "sets error when #update_default_branch fails unexpectedly" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case), "expected rename process to start successfully"
      RepositoryBranchRename.any_instance.stubs(:default_branch?).returns(true)
      Repository.any_instance.stubs(:point_to_new_default_branch).raises(StandardError)

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :update_default_branch_exception?
      assert_equal "update_default_branch_exception", T.must(renamer.rename).error_reason
      assert_equal "could not change default branch of #{@repo.name_with_owner}", T.must(renamer.rename).human_error_reason
    end

    test "sets error when #update_indexes_to_new_default_branch fails unexpectedly" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case), "expected rename process to start successfully"
      RepositoryBranchRename.any_instance.stubs(:default_branch?).returns(true)
      Repository.any_instance.stubs(:update_indexes_to_new_default_branch).raises(StandardError)

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :finish_rename_failed?
      assert_predicate renamer.rename, :update_indexes_to_new_default_branch_exception?
      assert_equal "update_indexes_to_new_default_branch_exception", T.must(renamer.rename).error_reason
      assert_equal "could not finish renaming branch 'cr-line-endings' to 'main'", T.must(renamer.rename).human_error_reason
    end

    test "sets error when #check_repository_writable fails unexpectedly" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")

      assert renamer.start_rename("main", actor: @user, entry_point: :test_case), "expected rename process to start successfully"

      Repository.any_instance.stubs(:writable?).raises(StandardError)

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :finish_rename_failed?
      assert_predicate renamer.rename, :check_repository_writable_exception?
      assert_equal "check_repository_writable_exception", T.must(renamer.rename).error_reason
      assert_match "#{@repo.name_with_owner} is archived, migrating, or disabled", T.must(renamer.rename).human_error_reason
    end

    test "sets error when #retarget_open_pull_requests fails unexpectedly" do
      RepositoryBranchRename.any_instance.stubs(:pull_requests_to_retarget).raises(StandardError)

      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case), "expected rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :finish_rename_failed?
      assert_predicate renamer.rename, :retarget_open_pull_requests_exception?
      assert_equal "retarget_open_pull_requests_exception", T.must(renamer.rename).error_reason
      assert_equal "could not finish renaming branch 'cr-line-endings' to 'main'", T.must(renamer.rename).human_error_reason
    end

    test "sets error when #retarget_draft_releases fails unexpectedly" do
      RepositoryBranchRename.any_instance.stubs(:draft_releases_to_retarget).raises(StandardError)

      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case), "expected rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :finish_rename_failed?
      assert_predicate renamer.rename, :retarget_draft_releases_exception?
      assert_equal "retarget_draft_releases_exception", T.must(renamer.rename).error_reason
      assert_equal "could not finish renaming branch 'cr-line-endings' to 'main'", T.must(renamer.rename).human_error_reason
    end

    test "sets error when #update_merge_queues fails unexpectedly" do
      @repo.stubs(:merge_queue_enabled?).raises(StandardError)

      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      refute renamer.start_rename("main", actor: @user, entry_point: :test_case)

      assert_predicate renamer.rename, :start_rename_failed?
      assert_predicate renamer.rename, :update_merge_queue_exception?
      assert_equal :update_merge_queue_exception, renamer.error
      assert_equal "could not start renaming branch 'cr-line-endings' to 'main'", renamer.human_error
    end

    test "sets error when #remove_old_protected_branch fails unexpectedly" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case), "expected rename process to start successfully"

      rule = ProtectedBranch.new
      rule.stubs(:destroy).raises(StandardError)
      RepositoryBranchRename.any_instance.stubs(:protected_branch_to_update).returns(rule)

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :finish_rename_failed?
      assert_predicate renamer.rename, :delete_old_protected_branch_exception?
      assert_equal "delete_old_protected_branch_exception", T.must(renamer.rename).error_reason
      assert_equal "could not finish renaming branch 'cr-line-endings' to 'main'", T.must(renamer.rename).human_error_reason

    end

    test "sets error when #update_pages_branch fails unexpectedly" do
      RepositoryBranchRename.any_instance.stubs(:update_pages?).raises(StandardError)

      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case), "expected rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :finish_rename_failed?
      assert_predicate renamer.rename, :update_pages_branch_exception?
      assert_equal "update_pages_branch_exception", T.must(renamer.rename).error_reason
      assert_equal "could not finish renaming branch 'cr-line-endings' to 'main'", T.must(renamer.rename).human_error_reason
    end

    test "sets error when #delete_old_branch_if_appropriate fails unexpectedly" do
      RepositoryBranchRename.any_instance.stubs(:ensure_new_branch_does_not_exist).returns(true)
      RepositoryBranchRename.any_instance.stubs(:ensure_old_branch_exists).returns(true)
      Git::Ref::Collection.any_instance.stubs(:find).raises(StandardError)

      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case), "expected rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :finish_rename_failed?
      assert_predicate renamer.rename, :delete_old_branch_if_appropriate_exception?
      assert_equal "delete_old_branch_if_appropriate_exception", T.must(renamer.rename).error_reason
      assert_equal "could not delete branch cr-line-endings", T.must(renamer.rename).human_error_reason

    end

    test "sets error when #mark_rename_as_finished fails unexpectedly" do
      RepositoryBranchRename.any_instance.expects(:update).with(state: :finished).raises(StandardError)

      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")
      assert renamer.start_rename("main", actor: @user, entry_point: :test_case), "expected rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :finish_rename_failed?
      assert_predicate renamer.rename, :mark_rename_as_finished_exception?
      assert_equal "mark_rename_as_finished_exception", T.must(renamer.rename).error_reason
      assert_equal "could not finish renaming branch 'cr-line-endings' to 'main'", T.must(renamer.rename).human_error_reason
    end

    test "sets error when #mark_obsolete_renames_as_moot fails unexpectedly" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")

      RepositoryBranchRename.stubs(:get_by_repo_and_old_name).raises(StandardError)

      assert renamer.start_rename("main", actor: @user, entry_point: :test_case), "expected rename process to start successfully"

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])

      assert_predicate T.must(renamer.rename).reload, :finish_rename_failed?
      assert_predicate renamer.rename, :mark_obsolete_renames_as_moot_exception?
      assert_equal "mark_obsolete_renames_as_moot_exception", T.must(renamer.rename).error_reason
      assert_equal "could not finish renaming branch 'cr-line-endings' to 'main'", T.must(renamer.rename).human_error_reason
    end

    test "logs Hydro event" do
      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
          "expected rename process to start successfully"
      end

      message = {
        repository: Hydro::EntitySerializer.repository(renamer.repository),
        repository_owner: Hydro::EntitySerializer.user(renamer.repository_owner),
        actor: Hydro::EntitySerializer.user(renamer.user),
        old_branch: "cr-line-endings",
        new_branch: "main",
        default_branch: false,
      }

      assert_hydro_published(message, schema: "github.repositories.v1.RenameBranch")
      assert_hydro_messages(count: 1, schema: "github.repositories.v1.RenameBranch")
    end

    test "updates branch protection rule that targets old branch" do
      rule = create(:protected_branch, name: "cr-line-endings", repository: @repo)

      renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "cr-line-endings")

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob])  do
        assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
          "expected rename process to start successfully"
      end

      assert ProtectedBranch.exists?(name: "main")
      refute ProtectedBranch.exists?(name: "cr-line-endings")
    end

    if GitHub.merge_queues_enabled?
      test "updates merge queue branch when configured via protected branches" do
        enable_feature_flag(:merge_queue)

        @repo.protect_branch(
          "master",
          creator: @repo.owner,
          enforce_merge_queue: true,
          entry_point: :test_case,
        )

        original_queue = @repo.reload.merge_queues.first
        original_queue.update!(merge_method: "squash")
        assert_equal "master", original_queue.branch

        renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: @repo, branch_name: "master")
        perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
          assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
            "expected rename process to start successfully"
        end

        assert_nil T.must(renamer.rename).reload.error_reason

        final_protected_branch = @repo.protected_branches.where(name: "main").first
        final_queue = @repo.merge_queues.where(branch: "main").first

        refute_nil final_protected_branch
        refute_nil final_queue
        assert_equal "main", final_queue.protected_branch.name
        assert_equal(
          "squash", final_queue.merge_method,
          "Expected queue settings not to change"
        )
        assert_equal(
          original_queue.id, final_queue.id,
          "Expected queue ID not to change, otherwise we lose queue contents and historical data"
        )

        assert_nil @repo.protected_branches.where(name: "master").first
        assert_nil @repo.merge_queues.where(branch: "master").first
      end

      test "update merge queue branch when configured via repo rulsets" do
        enable_feature_flag(:merge_queue)

        create(
          :repository_ruleset,
          source: @repo,
          conditions: [
            FactoryBot.build(:repository_rule_condition, :targets_default_branch),
          ],
          rule_configurations: [
            FactoryBot.build(:repository_rule_configuration, :merge_queue),
          ],
        )

        queue = MergeQueue.first
        assert_equal(
          "master", queue&.branch,
          "Invalid test assumption: assumed creating a repo ruleset for the "\
          "default branch would implicitly create a queue for 'master'."
        )

        renamer = RepositoryBranchRenamer.for_starting_rename_process(
          branch_name: "master",
          repository: @repo,
        )

        assert renamer.start_rename("main", actor: @user, entry_point: :test_case),
          "expected rename process to start successfully"

        assert_equal "main", T.must(queue).reload.branch
      end
    end
  end

  def get_commits(branch, repo: @repo, limit: 30)
    head = repo.rpc.read_refs["refs/heads/#{branch}"]
    oids = repo.rpc.list_revision_history(head)
    repo.rpc.read_commits(oids[0, limit])
  end

  # Takes a block that will run in between the sync and async portions of the RenameBranchOrchestration
  def start_pause_and_resume_rename(repository:, old_name:, new_name:, raises: false, jobs: [], &block)
    o = RepositoryOrchestration.rename_branch(
      repository: repository,
      actor: repository.owner,
      old_name: old_name,
      raw_new_name: new_name,
      entry_point: :test_case
    )
    RenameBranchOrchestration.stop_after_step = :create_new_branch
    o.execute

    yield(o) if block_given?

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob] + jobs) do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      if raises
        assert_raises(Orchestration::Error) { o.execute }
      else
        o.execute
      end
    end

    o
  end
end
