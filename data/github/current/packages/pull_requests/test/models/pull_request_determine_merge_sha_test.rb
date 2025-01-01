# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class PullRequestDetermineMergeShaTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :pull_request_source)
    @pull = PullRequest.create_for(@repo, {
      base:  "master",
      head:  "master-forward-2",
      user:  @user,
      issue: create(:issue, user: @user, repository: @repo),
    })
    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "detects the github-created merge commit" do
    @pull.merge(@user)
    assert_equal(@pull.reload.merged_commit.oid, @pull.determine_merge_sha)
  end

  test "finds merge commits on base with pr-head as a parent" do
    master = @repo.refs.find("master")
    merge_commit, _ = master.merge(@user, @pull.head_ref)
    assert_equal(merge_commit.oid, @pull.reload.determine_merge_sha)
  end

  test "finds octopus merges with pr-head as parent" do
    example_repo :octopus_merge, @repo
    pull = PullRequest.create_for(@repo, {
      base:  "master",
      head:  "arm-one",
      user:  @user,
      issue: create(:issue, user: @user, repository: @repo),
    })
    octo_merge_commit = @repo.refs.find("branch-with-octopus-merge-on-it").target
    @repo.refs.find("master").update(octo_merge_commit, @user)
    assert_equal(3, octo_merge_commit.parent_oids.size)
    assert_equal(octo_merge_commit.oid, pull.determine_merge_sha)
  end

  test "finds merges on master with pr-head as left parent (master as right)" do
    example_repo :merge_with_right_mainline, @repo
    pull = PullRequest.create_for(@repo, {
      base:  "master",
      head:  "topic",
      user:  @user,
      issue: create(:issue, user: @user, repository: @repo),
    })
    merge_commit = @repo.refs.find("after-merge").target
    @repo.refs.find("master").update(merge_commit, @user)
    assert_equal(merge_commit.oid, pull.determine_merge_sha)
  end

  test "finds nothing when no merge commits exist on base's history" do
    assert_nil @pull.determine_merge_sha
  end
end
