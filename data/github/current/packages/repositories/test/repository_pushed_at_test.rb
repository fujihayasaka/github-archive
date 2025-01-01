# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryPushedAtTest < GitHub::TestCase
  include PushTestHelper

  fixtures do
    @repo = create(:repository, from_example: :mojombo_grit)
  end

  test "high precision pushed_at timestamps work" do
    time   = Time.local(2110, 1, 23, 4, 56, 12, 123456)
    ref    = @repo.heads.find("master")
    before = ref.commit.parent_oids.first
    after  = ref.target_oid

    trigger_push_event(
      @repo.shard_path,
      @repo.owner.login,
      [["refs/heads/master", before, after]],
      time,
      perform_hydro_push_jobs: [HydroRepositoriesOnPushJob]
    )

    repo = Repository.find(@repo.id)
    assert_same_time time, repo.pushed_at
    assert_equal 123456, repo.pushed_at_usec
  end

  test "repository pushed_at changes after a push" do
    ref    = @repo.heads.find("master")
    before = ref.commit.parent_oids.first
    after  = ref.target_oid
    pushed_at_before = @repo.pushed_at

    trigger_push_event(
      @repo.shard_path,
      @repo.owner.login,
      [["refs/heads/master", before, after]],
      Time.current,
      perform_hydro_push_jobs: [HydroRepositoriesOnPushJob]
    )

    repo = Repository.find(@repo.id)
    assert pushed_at_before < repo.pushed_at
  end

  test "doesn't update when push is outdated" do
    ref    = @repo.heads.find("master")
    before = ref.commit.parent_oids.first
    after  = ref.target_oid
    pushed_at_before = @repo.pushed_at

    trigger_push_event(
      @repo.shard_path,
      @repo.owner.login,
      [["refs/heads/master", before, after]],
      Time.current - 7.days, # @repo.pushed_at will be now, so this is outdated
      perform_hydro_push_jobs: [HydroRepositoriesOnPushJob]
    )

    assert_equal pushed_at_before, @repo.reload.pushed_at
  end
end
