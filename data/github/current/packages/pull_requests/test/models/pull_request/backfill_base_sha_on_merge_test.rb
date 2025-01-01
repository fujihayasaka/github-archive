# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestBackfillBaseShaOnMergeTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  Spokesd.share_spokesdb(self)

  fixtures do
    @owner = create(:user, login: "ari")
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    @issue = create(:issue, user: @forker, repository: @source)
    @pull = PullRequest.create_for(@source, {
      base:  "master",
      head:  "#{@fork.user}:topic",
      user:  @issue.user,
      issue: @issue,
    })
  end

  setup do
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork
  end

  test "backfilling a normal merge" do
    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      success, message = @pull.merge(@owner, method: :merge)
      refute_nil success
    end

    expected_base_sha_on_merge = @pull.base_sha_on_merge
    refute_nil expected_base_sha_on_merge

    @pull.update_attribute(:base_sha_on_merge, nil)
    assert_nil @pull.base_sha_on_merge

    @pull.backfill_base_sha_on_merge

    refute_nil @pull.base_sha_on_merge
    assert_equal expected_base_sha_on_merge, @pull.base_sha_on_merge

    @pull.reload

    refute_nil @pull.base_sha_on_merge
    assert_equal expected_base_sha_on_merge, @pull.base_sha_on_merge
  end

  test "backfilling a squash merge" do
    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      success, message = @pull.merge(@owner, method: :squash)
      refute_nil success
    end

    expected_base_sha_on_merge = @pull.base_sha_on_merge
    refute_nil expected_base_sha_on_merge

    @pull.update_attribute(:base_sha_on_merge, nil)
    assert_nil @pull.base_sha_on_merge

    @pull.backfill_base_sha_on_merge

    refute_nil @pull.base_sha_on_merge
    assert_equal expected_base_sha_on_merge, @pull.base_sha_on_merge

    @pull.reload

    refute_nil @pull.base_sha_on_merge
    assert_equal expected_base_sha_on_merge, @pull.base_sha_on_merge
  end

  test "backfilling a rebase merge" do
    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      success, message = @pull.merge(@owner, method: :rebase)
      refute_nil success
    end

    expected_base_sha_on_merge = @pull.base_sha_on_merge
    refute_nil expected_base_sha_on_merge

    @pull.update_attribute(:base_sha_on_merge, nil)
    assert_nil @pull.base_sha_on_merge

    @pull.backfill_base_sha_on_merge

    refute_nil @pull.base_sha_on_merge
    assert_equal expected_base_sha_on_merge, @pull.base_sha_on_merge

    @pull.reload

    refute_nil @pull.base_sha_on_merge
    assert_equal expected_base_sha_on_merge, @pull.base_sha_on_merge
  end

  test "does not get confused by force-pushes after a merge" do
    Spokesd.enable_spokesd

    metadata = { message: "New commit", committer: @forker }

    old_head_commit_id = @fork.heads[@pull.head_ref].target_oid
    @fork.heads[@pull.head_ref].append_commit(metadata, @forker) do |files|
      files.add("README.md", "Something to read")
    end

    new_head_commit_oid = @fork.heads[@pull.head_ref].target_oid
    @pull.catch_up
    @pull.reload

    merge_commit_sha = T.let(nil, T.nilable(String))
    success = T.let(false, T::Boolean)

    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      success, merge_commit_sha = @pull.merge(@owner, method: :rebase)
      refute_nil success
    end

    expected_base_sha_on_merge = @pull.base_sha_on_merge
    refute_nil expected_base_sha_on_merge

    @pull.update_attribute(:base_sha_on_merge, nil)
    assert_nil @pull.base_sha_on_merge

    # Simulate a set of force-pushes
    create(:push, {
      pusher_id:     @owner.id,
      repository_id: @source.id,
      before:     merge_commit_sha,
      after:      old_head_commit_id,
      ref:        "refs/heads/#{@pull.base_ref}",
      pushed_at:  Time.now
    })

    create(:push, {
      pusher_id:     @owner.id,
      repository_id: @source.id,
      before:     old_head_commit_id,
      after:      merge_commit_sha,
      ref:        "refs/heads/#{@pull.base_ref}",
      pushed_at:  Time.now
    })

    @pull.backfill_base_sha_on_merge

    refute_nil @pull.base_sha_on_merge
    assert_equal expected_base_sha_on_merge, @pull.base_sha_on_merge

    @pull.reload

    refute_nil @pull.base_sha_on_merge
    assert_equal expected_base_sha_on_merge, @pull.base_sha_on_merge
  end
end
