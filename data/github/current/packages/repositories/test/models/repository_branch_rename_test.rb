# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryBranchRenameTest < GitHub::TestCase
  include HydroTestHelpers
  include BackgroundDeletesTestHelpers

  fixtures do
    @user = create(:user, login: "owner")
    @repo = create(:repository, owner: @user)
  end

  context "#human_error_reason" do
    test "explains failed_to_update_default_branch error reason" do
      rename = build(:repository_branch_rename, :errored,
        error_reason: :failed_to_update_default_branch, repository: @repo)
      assert_equal "could not change default branch of #{@repo.nwo}", rename.human_error_reason
    end

    test "explains pull_request_retarget_failed error reason" do
      rename = build(:repository_branch_rename, :errored,
        error_reason: :pull_request_retarget_failed, repository: @repo)
      assert_equal "could not update pull request's base branch", rename.human_error_reason
    end

    test "explains old_branch_dgit_error error reason" do
      rename = build(:repository_branch_rename, :errored,
        error_reason: :old_branch_dgit_error, repository: @repo)
      assert_equal "could not delete branch #{rename.old_name}", rename.human_error_reason
    end

    test "explains old_branch_hook_failure error reason" do
      rename = build(:repository_branch_rename, :errored,
        error_reason: :old_branch_hook_failure, repository: @repo)
      assert_equal "could not delete branch #{rename.old_name}", rename.human_error_reason
    end

    test "explains old_branch_not_deletable error reason" do
      rename = build(:repository_branch_rename, :errored,
        error_reason: :old_branch_not_deletable, repository: @repo)
      assert_equal "branch #{rename.old_name} cannot be deleted", rename.human_error_reason
    end

    test "explains new_branch_invalid_name error reason" do
      rename = build(:repository_branch_rename, :errored,
        error_reason: :new_branch_invalid_name, repository: @repo)
      assert_equal "'#{rename.new_name}' is not a valid branch name", rename.human_error_reason
    end

    test "explains new_branch_hook_failure error reason" do
      rename = build(:repository_branch_rename, :errored,
        error_reason: :new_branch_hook_failure, repository: @repo)
      assert_equal "could not create branch #{rename.new_name}", rename.human_error_reason
    end

    test "explains new_branch_dgit_error error reason" do
      rename = build(:repository_branch_rename, :errored,
        error_reason: :new_branch_dgit_error, repository: @repo)
      assert_equal "could not create branch #{rename.new_name}", rename.human_error_reason
    end

    test "explains new_branch_already_exists error reason" do
      rename = build(:repository_branch_rename, :errored,
        error_reason: :new_branch_already_exists, repository: @repo)
      assert_equal "branch #{rename.new_name} already exists", rename.human_error_reason
    end
  end

  context "Hydro logging" do
    test "logs event when rename is finished" do
      example_repo :simple, @repo
      rename = create(:repository_branch_rename, repository: @repo, old_name: "master",
        new_name: "pickles")
      rename.state = :finished
      assert rename.save

      message = {
        repository: Hydro::EntitySerializer.repository(rename.repository),
        repository_owner: Hydro::EntitySerializer.user(rename.repository.owner),
        actor: Hydro::EntitySerializer.user(rename.user),
        old_branch: "master",
        new_branch: "pickles",
        default_branch: true,
      }

      assert_hydro_published(message, schema: "github.repositories.v1.RenameBranch")
      assert_hydro_messages(count: 1, schema: "github.repositories.v1.RenameBranch")
    end

    test "does not log event when rename is marked as errored" do
      example_repo :simple, @repo
      rename = create(:repository_branch_rename, repository: @repo, old_name: "master",
        new_name: "pickles")
      rename.state = :errored
      assert rename.save

      assert_hydro_messages(count: 0, schema: "github.repositories.v1.RenameBranch")
    end
  end

  context "#protected_branch_to_update" do
    test "includes protected branch that explicitly targets branch being renamed" do
      example_repo :simple, @repo
      rule = create(:protected_branch, name: "cr-line-endings", repository: @repo)
      rename = build(:repository_branch_rename, repository: @repo, old_name: rule.name)

      result = rename.protected_branch_to_update

      assert_equal rule, result
    end

    test "does not include protected branch that indirectly targets branch being renamed" do
      example_repo :simple, @repo
      rule = create(:protected_branch, name: "cr-*", repository: @repo)
      rename = build(:repository_branch_rename, repository: @repo, old_name: "cr-line-endings")

      result = rename.protected_branch_to_update

      refute_equal result, rule
    end
  end

  context "#draft_releases_to_retarget" do
    test "includes draft release that explicitly targets branch being renamed" do
      release = create(:release, repository: @repo, target_commitish: "cr-line-endings",
        state: :draft)
      rename = build(:repository_branch_rename, repository: @repo,
        old_name: release.target_commitish)

      result = rename.draft_releases_to_retarget

      assert_equal [release], result
    end

    test "includes draft release that implicitly targets the default branch being renamed" do
      release = create(:release, repository: @repo, target_commitish: nil,
        state: :draft)
      rename = build(:repository_branch_rename, repository: @repo,
        old_name: @repo.default_branch)

      result = rename.draft_releases_to_retarget

      assert_equal [release], result
    end

    test "does not include published release" do
      release = create(:release, :published, repository: @repo,
        target_commitish: "cr-line-endings")
      rename = build(:repository_branch_rename, repository: @repo,
        old_name: release.target_commitish)

      result = rename.draft_releases_to_retarget

      refute_includes result, release
    end
  end

  context "#pull_requests_that_will_be_closed" do
    test "includes pull request in repo whose head branch is being renamed" do
      example_repo :simple, @repo
      pull = create(:pull_request, repository: @repo, base_ref: "master",
        head_ref: "cr-line-endings")
      rename = build(:repository_branch_rename, repository: @repo, old_name: pull.head_ref)

      result = rename.pull_requests_that_will_be_closed

      assert_equal [pull], result
    end

    test "does not include pull request in repo whose base branch is being renamed" do
      example_repo :simple, @repo
      pull = create(:pull_request, repository: @repo, base_ref: "master",
        head_ref: "cr-line-endings")
      rename = build(:repository_branch_rename, repository: @repo, old_name: pull.base_ref)

      result = rename.pull_requests_that_will_be_closed

      refute_includes result, pull
    end

    test "does not include pull request from fork whose head branch matches the head branch being renamed in parent repo" do
      example_repo :simple, @repo
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

      rename = build(:repository_branch_rename, repository: @repo, old_name: "master")

      result = rename.pull_requests_that_will_be_closed

      refute_includes result, pull
    end
  end

  context "#pull_requests_to_retarget" do
    test "includes pull request in repo whose base branch is being renamed" do
      example_repo :simple, @repo
      pull = create(:pull_request, repository: @repo, base_ref: "master",
        head_ref: "cr-line-endings")
      rename = build(:repository_branch_rename, repository: @repo, old_name: pull.base_ref)

      result = rename.pull_requests_to_retarget

      assert_equal [pull], result
    end

    test "does not include pull request in repo whose head branch is being renamed" do
      example_repo :simple, @repo
      pull = create(:pull_request, repository: @repo, base_ref: "master",
        head_ref: "cr-line-endings")
      rename = build(:repository_branch_rename, repository: @repo, old_name: pull.head_ref)

      result = rename.pull_requests_to_retarget

      refute_includes result, pull
    end

    test "does not include pull request from spammy fork" do
      example_repo :simple, @repo
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

      rename = build(:repository_branch_rename, repository: @repo, old_name: pull.base_ref)

      result = rename.pull_requests_to_retarget

      refute_includes result, pull
    end if GitHub.spamminess_check_enabled?

    test "includes pull request from fork whose base branch is being renamed" do
      example_repo :simple, @repo
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

      rename = build(:repository_branch_rename, repository: @repo, old_name: pull.base_ref)

      result = rename.pull_requests_to_retarget

      assert_equal [pull], result
    end

    test "does not include pull request in fork whose base branch has the same name as branch being renamed" do
      example_repo :simple, @repo
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

      rename = build(:repository_branch_rename, repository: @repo, old_name: pull.base_ref)

      result = rename.pull_requests_to_retarget

      refute_includes result, pull
    end
  end

  context "#count_of_pull_requests_to_retarget_by_repo_id" do
    test "returns a hash of pull requests to be retargeted, grouped by head repo" do
      example_repo :simple, @repo
      forking_user = create(:user, login: "forker")
      fork, status = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @repo.fork(forker: forking_user)
      end
      assert_equal :created, status, "fork should have been created"

      ref = fork.heads.find("master")
      refute_nil ref, "fork should have master branch"
      commit_meta = { message: "some changes", committer: forking_user }
      ref.append_commit(commit_meta, forking_user) { |files| files.add("file001", "foo") }

      # Fork pull request:
      create(:pull_request,
        issue: create(:issue, repository: @repo),
        base_repository: @repo,
        base_ref: "master",
        base_user: @user,
        head_repository: fork,
        head_ref: "master",
        head_user: forking_user)

      # Pull request within repo:
      create(:pull_request, repository: @repo, base_ref: "master",
        head_ref: "cr-line-endings")

      rename = build(:repository_branch_rename, repository: @repo, old_name: "master")

      expected = {
        fork.id => 1,
        @repo.id => 1
      }
      assert_equal expected, rename.count_of_pull_requests_to_retarget_by_repo_id
    end
  end

  context "validations" do
    test "requires a user at creation" do
      rename = RepositoryBranchRename.new
      refute_predicate rename, :valid?
      assert_includes rename.errors[:user], "can't be blank"
    end

    test "requires a repository" do
      rename = RepositoryBranchRename.new
      refute_predicate rename, :valid?
      assert_includes rename.errors[:repository], "must exist"
    end

    test "requires a repository that is not archived" do
      @repo.set_archived
      rename = RepositoryBranchRename.new(repository: @repo)
      refute_predicate rename, :valid?
      assert_includes rename.errors[:repository], "must not be archived, migrating, or disabled"
    end

    test "requires a repository that is not disabled" do
      @repo.access.disable("size", create(:staff_admin_user))
      rename = RepositoryBranchRename.new(repository: @repo)
      refute_predicate rename, :valid?
      assert_includes rename.errors[:repository], "must not be archived, migrating, or disabled"
    end

    test "requires a repository that is not locked for migration" do
      @repo.lock_for_migration
      rename = RepositoryBranchRename.new(repository: @repo)
      refute_predicate rename, :valid?
      assert_includes rename.errors[:repository], "must not be archived, migrating, or disabled"
    end

    test "requires an old name" do
      rename = RepositoryBranchRename.new
      refute_predicate rename, :valid?
      assert_includes rename.errors[:old_name], "can't be blank"
    end

    test "requires a new name" do
      rename = RepositoryBranchRename.new
      refute_predicate rename, :valid?
      assert_includes rename.errors[:new_name], "can't be blank"
    end

    test "disallows very long new_name" do
      rename = RepositoryBranchRename.new(old_name: "test", new_name: "a_very_long_name#{("🐹" * 300)}")
      refute_predicate rename, :valid?
      assert_includes rename.errors[:new_name], "is too long (maximum is 256 characters)"
    end

    test "requires old name and new name differ" do
      rename = RepositoryBranchRename.new(old_name: "test", new_name: "test")
      refute_predicate rename, :valid?
      assert_includes rename.errors[:new_name], "cannot be the same as the current branch"
    end

    test "allows same old name and new name when in errored state" do
      rename = RepositoryBranchRename.new(old_name: "test", new_name: "test",
        state: :errored)
      rename.valid? # trigger validation
      assert_empty rename.errors[:new_name]
    end

    test "requires old branch to exist on create" do
      example_repo :simple, @repo
      rename = RepositoryBranchRename.new(old_name: "this-branch-isnt-valid", repository: @repo)
      refute_predicate rename, :valid?
      assert_includes rename.errors[:old_name], "must exist"
    end

    test "does not make multiple new_name errors when new branch and old branch are the same" do
      example_repo :simple, @repo
      rename = RepositoryBranchRename.new(old_name: "master", repository: @repo,
        new_name: "master")
      refute_predicate rename, :valid?
      assert_equal ["cannot be the same as the current branch"], rename.errors[:new_name]
    end

    test "allows missing old branch if not in 'started' state" do
      rename = RepositoryBranchRename.new(old_name: "this-branch-isnt-valid", repository: @repo,
        state: :finished)
      rename.valid? # trigger validation
      assert_empty rename.errors[:old_name]
    end

    test "requires new branch to not already exist on create" do
      example_repo :simple, @repo
      rename = RepositoryBranchRename.new(new_name: "cr-line-endings", repository: @repo)
      refute_predicate rename, :valid?
      assert_includes rename.errors[:new_name], "already exists"
    end

    test "allows existing new branch if in not in 'started' state" do
      example_repo :simple, @repo
      rename = RepositoryBranchRename.new(new_name: "cr-line-endings", repository: @repo,
        state: :errored)
      rename.valid? # trigger validation
      assert_empty rename.errors[:new_name]
    end

    test "sets default_branch based on repository and old_name" do
      rename = RepositoryBranchRename.new(old_name: @repo.default_branch, repository: @repo)
      assert_nil rename.default_branch
      rename.valid? # trigger validation

      assert_predicate rename, :default_branch?
    end

    test "requires no existing branch protection rules that directly target new branch name" do
      example_repo :simple, @repo
      rule = create(:protected_branch, name: "new-name", repository: @repo)
      rename = RepositoryBranchRename.new(old_name: @repo.default_branch, new_name: "new-name",
        repository: @repo)
      rename.valid? # trigger validation
      assert_includes rename.errors[:base], "delete the branch protection rule for \"new-name\" and try again"
    end

    test "allows existing branch protection rules that indirectly target new branch name" do
      example_repo :simple, @repo
      rule = create(:protected_branch, name: "*", repository: @repo)
      rename = RepositoryBranchRename.new(old_name: @repo.default_branch, new_name: "new-name",
        repository: @repo)
      rename.valid? # trigger validation
      assert_empty rename.errors[:base]
    end
  end

  context "audit log" do
    test "instruments a repo.rename_branch event for a user-owned repo when finished" do
      example_repo :simple, @repo
      rename = create(:repository_branch_rename, repository: @repo, old_name: "cr-line-endings",
        new_name: "pickles", old_sha: "cdbef")
      expected_payload = {
        old_sha: "cdbef",
        old_branch: "cr-line-endings",
        new_branch: "pickles",
        default_branch: false,
        repo: @repo.nwo,
        actor: rename.user.login,
        user: @user.login,
      }
      rename.state = :finished
      events = subscribe("repo.rename_branch")

      rename.save

      assert event = events.pop, "expected an event to be instrumented"
      assert_subset_hash expected_payload, event.payload
    end

    test "instruments a repo.rename_branch event for an org-owned repo when finished" do
      org = create(:organization)
      org_repo = create(:repository, owner: org, from_example: :simple)
      rename = create(:repository_branch_rename, repository: org_repo, old_name: "master",
        new_name: "cucumbers", old_sha: "cdbef")
      expected_payload = {
        old_sha: "cdbef",
        old_branch: "master",
        new_branch: "cucumbers",
        default_branch: true,
        repo: org_repo.nwo,
        actor: rename.user.login,
        org: org.login,
      }
      rename.state = :finished
      events = subscribe("repo.rename_branch")

      rename.save

      assert event = events.pop, "expected an event to be instrumented"
      assert_subset_hash expected_payload, event.payload
    end
  end

  test "is deleted with repository" do
    repo = create(:public_repository, from_example: :simple)
    rename = create(:repository_branch_rename, repository: repo, old_name: "master", new_name: "pickles")
    other_repo = create(:public_repository, from_example: :simple)
    other_rename = create(:repository_branch_rename, repository: other_repo, old_name: "master", new_name: "pickles")

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = repo
      config.expect_destroyed = [rename]
      config.expect_not_destroyed = [other_rename]
    end
  end
end
