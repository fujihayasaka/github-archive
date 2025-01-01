# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryWithGitReposOnDiskMoreTest < GitHub::TestCase
  include RepositoryOnDiskFixtures
  include HydroMessageJobTestHelpers

  setup do
    @grit.update_default_branch("master")
  end

  test "doesn't return recently touched branches with existing newly-closed pull requests on the same repo" do
    default = @grit.heads.find(@grit.default_branch)

    branch_without_pr_name = "diverge"
    branch_with_pr_name    = "lazy_delegator"

    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      branch_without_pr_ref      = @grit.heads.find_or_build(branch_without_pr_name)
      branch_without_pr_metadata = { message: "tmp commit 1", committer: @defunkt }
      branch_without_pr_commit   = @grit.commits.create(branch_without_pr_metadata, default.target_oid) do |files|
        files.add("tmp1.txt", "some content")
      end
      branch_without_pr_ref.update(branch_without_pr_commit, @defunkt)

      branch_with_pr_ref      = @grit.heads.find_or_build(branch_with_pr_name)
      branch_with_pr_metadata = { message: "tmp commit 2", committer: @defunkt }
      branch_with_pr_commit   = @grit.commits.create(branch_with_pr_metadata, default.target_oid) do |files|
        files.add("tmp2.txt", "some content")
      end
      branch_with_pr_ref.update(branch_with_pr_commit, @defunkt)
    end

    issue = create(:issue,
      user: @grit.owner,
      repository: @grit,
      body: "you say you got a lotta whips, well i got a Lot",
    )

    PullRequest.create(
      repository: @grit,
      base_repository: @grit,
      base_user: @grit.owner,
      base_ref: @grit.default_branch,
      head_repository: @grit,
      head_user: @grit.owner,
      head_ref: branch_with_pr_name,
      issue: issue,
    )

    issue.close(@grit.owner)
    issue.update(closed_at: 59.minutes.ago)

    branches = @grit.recently_touched_branches_for(@defunkt)

    assert_equal 1, branches.size
    assert_equal branch_without_pr_name, branches.first[:name]
  end

  test "doesn't return recently touched branches with existing newly-closed pull requests from a forked repo" do
    grit_fork = create(:fork_repository, forker: create(:user), fork_repo: @grit)
    grit_fork.root.reload
    example_repo :mojombo_grit, grit_fork # rubocop:disable GitHub/UseFromExampleInRepositoryFactory

    grit_fork_default = grit_fork.heads.find(grit_fork.default_branch)
    parent_oid = grit_fork_default.target_oid

    branch_without_pr_name = "diverge"
    branch_with_pr_name    = "lazy_delegator"


    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      branch_without_pr_ref      = grit_fork.heads.find_or_build(branch_without_pr_name)
      branch_without_pr_metadata = { message: "tmp commit 1", committer: grit_fork.owner }
      branch_without_pr_commit   = grit_fork.commits.create(branch_without_pr_metadata, parent_oid) do |files|
        files.add("tmp1.txt", "some content")
      end
      branch_without_pr_ref.update(branch_without_pr_commit, grit_fork.owner)

      branch_with_pr_ref      = grit_fork.heads.find_or_build(branch_with_pr_name)
      branch_with_pr_metadata = { message: "tmp commit 2", committer: grit_fork.owner }
      branch_with_pr_commit   = grit_fork.commits.create(branch_with_pr_metadata, parent_oid) do |files|
        files.add("tmp2.txt", "some content")
      end
      branch_with_pr_ref.update(branch_with_pr_commit, grit_fork.owner)
    end

    grit_fork.reload

    issue = create(:issue,
      user: grit_fork.owner,
      repository: @grit,
      body: "you say you got a lotta whips, well i got a Lot",
    )

    PullRequest.create(
      repository: @grit,
      base_repository: @grit,
      base_user: @grit.owner,
      base_ref: @grit.default_branch,
      head_repository: grit_fork,
      head_user: grit_fork.owner,
      head_ref: branch_with_pr_name,
      issue: issue,
      user: grit_fork.owner,
    )

    issue.close(grit_fork.owner)
    issue.update(closed_at: 59.minutes.ago)

    branches = grit_fork.recently_touched_branches_for(grit_fork.owner)

    assert_equal 1, branches.size
    assert_equal branch_without_pr_name, branches.first[:name]
  end

  test "doesn't return recently touched branches with existing newly-closed pull requests from parent advisory repo" do
    author = create(:user)
    advisory = create(:repository_advisory, repository: @grit, author: author)
    example_repo :pull_request_source, @grit
    GitHub.context.push(actor_id: author.id)

    workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, author)
    workspace_repo.save!
    example_repo :pull_request_fork, workspace_repo

    parent_oid = workspace_repo.heads.find(workspace_repo.default_branch).target_oid
    branch_with_pr_name = "bugfix-🐛-1"
    branch_without_pr_name = "bugfix-🐛-2"


    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      branch_with_pr_ref = workspace_repo.heads.find_or_build(branch_with_pr_name)
      branch_with_pr_commit = workspace_repo.commits.create({ message: "commit 1", committer: workspace_repo.owner }, parent_oid) do |files|
        files.add("tmp3.txt", "some content 1")
      end
      branch_with_pr_ref.update(branch_with_pr_commit, workspace_repo.owner)

      branch_without_pr_ref = workspace_repo.heads.find_or_build(branch_without_pr_name)
      branch_without_pr_commit = workspace_repo.commits.create({ message: "commit 2", committer: workspace_repo.owner }, parent_oid) do |files|
        files.add("tmp4.txt", "some content 2")
      end
      branch_without_pr_ref.update(branch_without_pr_commit, workspace_repo.owner)
    end

    issue = create(:issue,
      user: workspace_repo.owner,
      repository: workspace_repo
    )

    PullRequest.create(
      repository: workspace_repo,
      base_repository: @grit,
      head_repository: workspace_repo,
      base_ref: @grit.default_branch,
      head_ref: branch_with_pr_name,
      base_user: @grit.owner,
      head_user: workspace_repo.owner,
      issue: issue,
      user: workspace_repo.owner
    )

    branches = workspace_repo.recently_touched_branches_for(workspace_repo.owner)

    assert_equal 1, branches.size
    assert_equal branch_without_pr_name, branches.first[:name]
  end

  test "doesn't error on recently touched branches when the repo has an invalid parent_id" do
    # Give the repo an invalid parent ID
    @grit.parent_id = Repository.maximum(:id) + 1000


    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      branch1_ref      = @grit.heads.find("diverge")
      branch1_metadata = { message: "tmp commit 1", committer: @defunkt }
      branch1_ref.append_commit(branch1_metadata, @defunkt) do |files|
        files.add("tmp1.txt", "some content")
      end

      branch2_ref      = @grit.heads.find("lazy_delegator")
      branch2_metadata = { message: "tmp commit 2", committer: @defunkt }
      branch2_ref.append_commit(branch2_metadata, @defunkt) do |files|
        files.add("tmp2.txt", "some content")
      end
    end

    branches = @grit.recently_touched_branches_for(@defunkt)

    assert_equal 2, branches.size
  end

  test "doesn't show branches that have been deleted" do
    Push.any_instance.stubs(:instrument_push)
    create(:push, repository: @grit, pusher: @defunkt, ref: "refs/heads/somebranch",
      after: "3b1039786c4c24b7a94987dc92fa4a92636c4e02", created_at: 5.minutes.ago)
    create(:push, repository: @grit, pusher: @defunkt, ref: "refs/heads/somebranch",
      after: GitHub::NULL_OID)
    assert_empty @grit.recently_touched_branches_for(@defunkt)
  end

  test "doesn't show branches that match the default branch" do
    default = @grit.heads.find(@grit.default_branch)
    branch  = "new_empty"

    @grit.heads.create(branch, default.target_oid, @defunkt)

    branches = @grit.recently_touched_branches_for(@defunkt)

    assert_equal [], branches
  end

  test "doesn't show branches that match the given commit oid" do
    ref = @grit.heads.find("diverge")
    branch  = "new_empty"

    ref = @grit.heads.create(branch, ref.target_oid, @defunkt)

    branches = @grit.recently_touched_branches_for(@defunkt, ref.target_oid)

    assert_equal [], branches
  end

  test "doesn't show branches in a fork that match the equivalent branch on the parent" do
    user = create(:user)
    @fork = create(:fork_repository, forker: user, fork_repo: @grit, from_example: :mojombo_grit)

    branch = "diverge"
    ref    = @fork.heads.find(branch)
    oid    = ref.target_oid
    ref.delete(user)

    # make the fork's default branch point somewhere else
    ref = @fork.heads.find(@fork.default_branch)
    metadata = { message: "tmp commit 2", committer: user }
    ref.append_commit(metadata, user) do |files|
      files.add("tmp2.txt", "some content")
    end

    @fork.heads.create(branch, oid, user)
    @fork.heads.create("newthing", @grit.default_oid, user)

    branches = @fork.recently_touched_branches_for(user)

    assert_equal [], branches
  end

  test "doesn't show branches that are behind" do
    master = @grit.heads.find("master")
    branch = "behind_master"

    @grit.heads.create(branch, master.commit.parent_oids.first, @defunkt)

    branches = @grit.recently_touched_branches_for(@defunkt)

    assert_equal [], branches
  end

  test "changes visibility on changing to public" do
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @ambition.toggle_visibility(actor: @ambition.owner) }
    assert @ambition.reload.public?
    assert !@ambition.private?
  end

  test "hides empty repos from google" do
    assert create(:repository).hide_from_google?
  end

  test "hides forks with no unique code from google" do
    @grit.owner.star(@grit)
    @defunkt.star(@grit)

    example_repo :mojombo_grit, @grit

    only = [AddToSearchIndexJob]
    grit_fork, _ = perform_enqueued_jobs(only: only) do
      @grit.fork(forker: create(:user))
    end

    grit_fork.reload

    assert grit_fork.hide_from_google?
  end

  test "hides non-notable forks from google even if they have unique code" do
    example_repo :mojombo_grit, @grit

    only = [RepositoryOrchestrationJob]
    grit_fork, _ = perform_enqueued_jobs(only: only) do
      @grit.fork(forker: create(:user))
    end

    grit_fork.reload

    metadata = { message: "blah", committer: grit_fork.owner }

    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      grit_fork.heads.find("master").append_commit(metadata, grit_fork.owner) {}
    end

    grit_fork.reload

    assert grit_fork.hide_from_google?

    grit_fork.update!(stargazer_count: 100)
    refute grit_fork.hide_from_google?

    grit_fork.root.update!(stargazer_count: 2)
    grit_fork.update!(stargazer_count: 1)
    grit_fork.root.reload

    assert grit_fork.hide_from_google?
  end

  test "shows renamed forks to google if they have unique code" do
    example_repo :mojombo_grit, @grit

    only = [RepositoryOrchestrationJob]
    grit_fork, _ = perform_enqueued_jobs(only: only) do
      @grit.fork(forker: create(:user))
    end

    grit_fork.reload

    metadata = { message: "blah", committer: grit_fork.owner }
    grit_fork.heads.find("master").append_commit(metadata, grit_fork.owner) {}

    grit_fork.reload

    assert grit_fork.hide_from_google?

    grit_fork.rename "ruby-git"

    refute grit_fork.hide_from_google?
  end

  test "returns contributor ids" do
    CommitContribution.backfill!(@simple)
    expected = %w(nickh rsanheim).map { |login| User.find_by_login(login).id }.sort
    assert_equal expected, @simple.contributor_ids.sort
  end

  test "returns a subset of contributor ids" do
    CommitContribution.backfill!(@simple)
    user = create :user, login: "nobody"
    ids  = [User.find_by_login("nickh").id, user.id]
    assert_equal ids[0...1], @simple.contributor_ids(ids)
  end

  test "checks an individual contributor" do
    CommitContribution.backfill!(@simple)
    user = create :user, login: "nobody"
    assert @simple.contributor? User.find_by_login("nickh")
    refute @simple.contributor? user
  end

  test "checks for pull requests as contributions from a user" do
    user = create(:user)
    example_repo :simple, @grit

    refute @grit.contributor?(user, type: PullRequest)

    create(:pull_request,
      repository: @grit,
      base_repository: @grit,
      base_user: user,
      base_ref: "master",
      head_repository: @grit,
      head_user: user,
      head_ref: @grit.heads.find("cr-line-endings").name,
      issue: create(:issue, user: user, repository: @grit),
    )

    assert @grit.contributor?(user, type: PullRequest)
  end

  test "checks for issues as contributions from a user" do
    user = create(:user)
    example_repo :simple, @grit
    create(:pull_request,
      repository: @grit,
      base_repository: @grit,
      base_user: user,
      base_ref: "master",
      head_repository: @grit,
      head_user: user,
      head_ref: @grit.heads.find("cr-line-endings").name,
      issue: create(:issue, user: user, repository: @grit),
    )

    refute @grit.contributor?(user, type: Issue)

    create(:issue, repository: @grit, user: user)

    assert @grit.contributor?(user, type: Issue)
  end

  test "excludes contributions from ghost" do
    CommitContribution.backfill!(@simple)
    CommitContribution.create \
      repository: @simple,
      user: User.ghost,
      commit_count: 1
    expected = %w(nickh rsanheim).map { |login| User.find_by_login(login).id }.sort
    assert_equal expected, @simple.contributor_ids.sort
  end

  context "#contributor_count_or" do
    test "counts contributors" do
      CommitContribution.backfill!(@simple)
      assert_equal 2, @simple.contributor_count_or(0)
    end

    test "uses its fallback value if uncomputable" do
      @simple.rpc.stubs(:contributor_shortlog).raises(GitRPC::Timeout)
      assert_equal 123, @simple.contributor_count_or(123)
    end
  end
end
