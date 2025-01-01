# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestRevertableByTest < GitHub::TestCase
  include PullRequestSynchronizationTestHelpers

  setup do
    Spokesd.enable_spokesd

    @owner = create(:user)
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    @fork = create(:fork_repository, forker: create(:user), fork_repo: @source, from_example: :pull_request_fork)

    @same_repo_pull = PullRequest.create_for!(@fork,
      user: @fork.owner,
      base: "#{@fork.owner}:master",
      head: "#{@fork.owner}:topic",
      title: "same repo pull",
      body: "blah")

    assert @same_repo_pull.merge.first

    @cross_repo_pull = PullRequest.create_for!(@source,
      user: @fork.owner,
      base: "#{@source.owner}:master",
      head: "#{@fork.owner}:topic",
      title: "cross repo pull",
      body: "blah")

    assert @cross_repo_pull.merge.first
  end

  test "users with push access to the base or head repository can revert" do
    assert @cross_repo_pull.revertable_by?(@source.owner)
    assert @cross_repo_pull.revertable_by?(@fork.owner)
  end

  test "users with push access cannot revert when base repo is locked for migration" do
    @source.lock_for_migration

    refute_operator @cross_repo_pull, :revertable_by?, @source.owner
    refute_operator @cross_repo_pull, :revertable_by?, @fork.owner
  end

  test "users with push access cannot revert when base repo is archived" do
    @source.set_archived

    refute_operator @cross_repo_pull, :revertable_by?, @source.owner
    refute_operator @cross_repo_pull, :revertable_by?, @fork.owner
  end

  test "users who own a fork can revert" do
    user = create(:user)
    assert !@cross_repo_pull.revertable_by?(user)

    create(:fork_repository, forker: user, fork_repo: @cross_repo_pull.base_repository)
    assert @cross_repo_pull.reload.revertable_by?(user)
  end

  test "users with push access to a fork can revert" do
    user = create(:user)
    other_fork_owner = create(:user)
    other_fork = create(:fork_repository, forker: other_fork_owner, fork_repo: @cross_repo_pull.base_repository)

    assert !@cross_repo_pull.revertable_by?(user)

    other_fork.add_member(user)

    assert @cross_repo_pull.reload.revertable_by?(user)
  end

  test "users with only pull access to a fork cannot revert" do
    org = create(:organization, admin: @owner)
    org_fork = create(:fork_repository, forker: @owner, organization: org, fork_repo: @source)
    user = create(:user)

    assert !@cross_repo_pull.revertable_by?(user)

    team = create(:team, organization: org, permission: "pull")
    team.add_member(user)

    assert team.member?(user)
    assert !@cross_repo_pull.reload.revertable_by?(user)
  end

  test "async_pushable_repo_for chooses which repository to revert from in the right order" do
    user = create(:user)

    assert_nil @cross_repo_pull.async_pushable_repo_for(user).sync

    random_pushable_fork = create(:fork_repository, forker: create(:user), fork_repo: @source)
    random_pushable_fork.add_member(user)

    assert_equal random_pushable_fork, @cross_repo_pull.reload.async_pushable_repo_for(user).sync

    users_fork = create(:fork_repository, forker: user, fork_repo: @source)

    assert_equal users_fork, @cross_repo_pull.reload.async_pushable_repo_for(user).sync

    @fork.add_member(user)

    assert_equal @fork, @cross_repo_pull.reload.async_pushable_repo_for(user).sync

    @source.add_member(user)

    assert_equal @source, @cross_repo_pull.reload.async_pushable_repo_for(user).sync
  end

  test "cannot be reverted if the pull wasn't merged" do
    @cross_repo_pull.update!(merged_at: nil)
    assert !@cross_repo_pull.revertable_by?(@source.owner)

    @same_repo_pull.update!(merged_at: nil)
    assert !@same_repo_pull.revertable_by?(@fork.owner)
  end

  test "cannot be reverted if the base is missing" do
    @source.heads.find("master").delete(@source.owner)
    assert_nil @source.heads.read("master").target_oid

    # We need to reload these, since #merge can memoize a ref_to_sha call
    @cross_repo_pull.reload
    assert !@cross_repo_pull.revertable_by?(@source.owner)

    @fork.heads.find("master").delete(@fork.owner)
    assert_nil @fork.heads.read("master").target_oid

    @same_repo_pull.reload
    assert !@same_repo_pull.revertable_by?(@fork.owner)
  end

  test "cannot be reverted if the pull was merged via fast forward" do
    master = @source.heads.find("master")
    topic  = @source.heads.create("topic",
                                  master.target_oid,
                                  @source.owner)

    metadata = {
      committer: @source.owner,
      message: "blah",
    }

    commit = topic.append_commit(metadata, @source.owner) do |files|
      files.add("blah.txt", "blah")
    end

    pull = PullRequest.create_for!(@source,
      user: @source.owner,
      base: "#{@source.owner}:master",
      head: "#{@source.owner}:topic",
      title: "blah",
      body: "blahblah")

    with_enqueued_pr_sync_jobs do
      master.update(commit.oid, @source.owner)
    end

    pull.reload

    assert pull.merged?
    refute pull.revertable_by?(@source.owner)
  end
end
