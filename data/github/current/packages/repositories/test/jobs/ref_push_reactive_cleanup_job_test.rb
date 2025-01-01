# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RefPushReactiveCleanupJobTest < GitHub::TestCase
  include JobTestHelper
  include DogstatsTestHelpers
  include HydroMessageJobTestHelpers

  fixtures do
    @user = create :user
    @repo = create :repository, owner: @user, from_example: :simple

    example_repo_snapshot
  end

  setup do
    example_repo_restore

    enable_feature_flag(:ref_push_reactive_cleanup)
  end

  test "cleans up deleted branch" do
    pushed_at = Time.now - 2.seconds
    # A leftover RefPush that was not cleaned up properly
    RefPush.create!(repository: @repo, pusher: @user, ref: "refs/heads/deleted", after: "a" * 40, pushed_at: pushed_at - 1.second)
    # A push that deleted the branch
    Push.create!(repository: @repo, ref: "refs/heads/deleted", after: GitHub::NULL_OID, pushed_at: pushed_at)

    RefPushReactiveCleanupJob.perform_now(@repo.id, ["refs/heads/deleted"])

    assert_equal 0, RefPush.where(repository: @repo, ref: "refs/heads/deleted").count
  end

  test "does not clean up branch that was re-created" do
    pushed_at = Time.now - 2.seconds
    # A push that was a deletion
    Push.create!(repository: @repo, ref: "refs/heads/valid", after: GitHub::NULL_OID, pushed_at: pushed_at - 2.seconds)
    # A push that was not a deletion
    Push.create!(repository: @repo, ref: "refs/heads/valid", after: "b" * 40, pushed_at: pushed_at - 1.second)
    RefPush.create!(repository: @repo, pusher: @user, ref: "refs/heads/valid", after: "a" * 40, pushed_at: pushed_at)

    RefPushReactiveCleanupJob.perform_now(@repo.id, ["refs/heads/valid"])

    assert_equal 1, RefPush.where(repository: @repo, ref: "refs/heads/valid").count
  end

  test "cleans up deleted branch with the same pushed_at where the deletion happened last" do
    pushed_at = Time.now - 2.seconds
    # A leftover RefPush that was not cleaned up properly
    RefPush.create!(repository: @repo, pusher: @user, ref: "refs/heads/deleted", after: "b" * 40, pushed_at: pushed_at)
    # A push that deleted the branch
    Push.create!(repository: @repo, ref: "refs/heads/deleted", before: "b" * 40, after: GitHub::NULL_OID, pushed_at: pushed_at)
    # A push at the same time that was not a deletion
    Push.create!(repository: @repo, ref: "refs/heads/deleted", before: "a" * 40, after: "b" * 40, pushed_at: pushed_at)

    RefPushReactiveCleanupJob.perform_now(@repo.id, ["refs/heads/deleted"])

    assert_equal 0, RefPush.where(repository: @repo, ref: "refs/heads/deleted").count
  end

  test "does not clean up deleted branch with the same pushed_at where the deletion happened first" do
    pushed_at = Time.now - 2.seconds
    RefPush.create!(repository: @repo, pusher: @user, ref: "refs/heads/valid", after: "a" * 40, pushed_at: pushed_at)
    # A push that deleted the branch (happened first)
    Push.create!(repository: @repo, ref: "refs/heads/valid", before: "b" * 40, after: GitHub::NULL_OID, pushed_at: pushed_at)
    # A push at the same time that was not a deletion (happened last)
    Push.create!(repository: @repo, ref: "refs/heads/valid", before: GitHub::NULL_OID, after: "a" * 40, pushed_at: pushed_at)

    RefPushReactiveCleanupJob.perform_now(@repo.id, ["refs/heads/valid"])

    assert_equal 1, RefPush.where(repository: @repo, ref: "refs/heads/valid").count
  end

  test "cleans up creation/deletion pair that occurs at the same pushed_at when branch no longer exists" do
    enable_feature_flag(:ref_push_reactive_cleanup_git_exists)

    pushed_at = Time.now - 2.seconds
    RefPush.create!(repository: @repo, pusher: @user, ref: "refs/heads/valid", after: "a" * 40, pushed_at: pushed_at)
    # A creation and deletion that form a loop
    Push.create!(repository: @repo, ref: "refs/heads/valid", before: "a" * 40, after: GitHub::NULL_OID, pushed_at: pushed_at)
    Push.create!(repository: @repo, ref: "refs/heads/valid", before: GitHub::NULL_OID, after: "a" * 40, pushed_at: pushed_at)

    RefPushReactiveCleanupJob.perform_now(@repo.id, ["refs/heads/valid"])

    assert_equal 0, RefPush.where(repository: @repo, ref: "refs/heads/valid").count
  end

  test "does not clean up creation/deletion pair that occurs at the same pushed_at when branch still exists" do
    enable_feature_flag(:ref_push_reactive_cleanup_git_exists)

    pushed_at = Time.now - 2.seconds
    RefPush.create!(repository: @repo, pusher: @user, ref: "refs/heads/valid", after: "a" * 40, pushed_at: pushed_at)
    # A creation and deletion that form a loop
    Push.create!(repository: @repo, ref: "refs/heads/valid", before: "a" * 40, after: GitHub::NULL_OID, pushed_at: pushed_at)
    Push.create!(repository: @repo, ref: "refs/heads/valid", before: GitHub::NULL_OID, after: "a" * 40, pushed_at: pushed_at)

    @repo.heads.create("valid", @repo.default_branch_ref.commit.oid, @repo.owner)

    RefPushReactiveCleanupJob.perform_now(@repo.id, ["refs/heads/valid"])

    assert_equal 1, RefPush.where(repository: @repo, ref: "refs/heads/valid").count
  end

end
