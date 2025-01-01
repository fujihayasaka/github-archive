# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class GistPushJobTest < GitHub::TestCase
  include JobTestHelper
  include HydroTestHelpers

  fixtures do
    @user = create(:user, login: "tonystark")
    @pusher = create(:user, login: "defunkt")
    @gist = GistHelpers.generate user: @user,
      contents: [{ name: "1", value: "random content" }]
    @soft_deleted_gist = GistHelpers.generate user: @user,
      contents: [{ name: "2", value: "an archived gist" }]
    @refs = [
        ["refs/heads/main", "4c8124ffcf4039d292442eeccabdeca5af5c5017", "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425"],
        ["refs/heads/dead", "12521512512515325h4234v3c322323423423423", GitHub::NULL_OID],
        ["refs/heads/awesome", "5dea2f86730665894cf03f2b1fac98c1217a9fb4", "451a4d8118d2c9c746c687efceaacac799e67ad9"],
        ["refs/heads/lame", GitHub::NULL_OID, "251a4d8118d2c9c746c687efceaacac799e67ad9"]]

    @input = build_input @refs

  end

  setup do
    reset_cache
  end

  test "runs gist-push job" do
    GistPushJob.any_instance.expects(:perform)
    push_test! @gist.shard_path
  end

  test "runs gist-push job anonymously" do
    GistPushJob.any_instance.expects(:perform)
    anonymous_push_test! @gist.shard_path
  end

  test "updates the gist's timestamp" do
    reset_timestamp
    push_test! @gist.shard_path

    @gist.reload
    assert @gist.updated_at != Time.at(420)
  end

  test "updates the gist's pushed counts" do
    pushed_count = @gist.pushed_count
    pushed_count_since_maintenance = @gist.pushed_count_since_maintenance

    push_test! @gist.shard_path

    assert_equal pushed_count.next, @gist.reload.pushed_count
    assert_equal pushed_count_since_maintenance.next, @gist.reload.pushed_count_since_maintenance
  end

  test "enqueues only one search index job" do
    AddToSearchIndexJob.any_instance.expects(:perform).once
    perform_enqueued_jobs only: [GistSynchronizeSearchIndexJob, AddToSearchIndexJob] do
      push_test! @gist.shard_path
    end
  end

  test "queueing backup job" do
    GitHub.stubs(realtime_backups_enabled?: true)
    Gist.any_instance.stubs(:backup_queue).returns("backup_fs123")
    simple_push!
    assert_enqueued_jobs 1, only: RepositoryBackupNgJob, queue: RepositoryBackupNgJob.queue_name
  end

  test "gracefully handles a soft-deleted gist gist" do
    shard_path = @soft_deleted_gist.shard_path
    @soft_deleted_gist.remove
    push_test! shard_path, [
      GitHub::NULL_OID,
      "251a4d8118d2c9c746c687efceaacac799e67ad9",
      "refs/heads/main"].join(" ")
  end

  test "retries when killed" do
    assert_retry_on_dirty_exit job: GistPushJob, args: [@gist.shard_path, @pusher, @input]
  end

  test "updates disk usage stats" do
    GistDiskUsageJob.expects(:enqueue_once_per_interval).with(args: [@gist.id], interval: 60 * 60)
    simple_push!
  end

  test "message includes GistPush when a gist is pushed up" do
    assert_hydro_messages(count: 0, schema: "github.v1.GistPush")
    pushed_at = Time.current
    expected_message = {
      actor: Hydro::EntitySerializer.user(@pusher),
      owner: Hydro::EntitySerializer.user(@gist.owner),
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      gist: Hydro::EntitySerializer.gist(@gist),
      ref_updates: [{
        ref_name: "refs/heads/main",
        previous_ref_oid: GitHub::NULL_OID,
        current_ref_oid: "251a4d8118d2c9c746c687efceaacac799e67ad9",
      }],
      feature_flags: @gist.feature_flags_on_gists,
      pushed_at: pushed_at,
    }

    GistPushJob.perform_now(
      @gist.shard_path,
      @pusher.login,
      [["refs/heads/main", GitHub::NULL_OID, "251a4d8118d2c9c746c687efceaacac799e67ad9"]],
      pushed_at,
      nil, # push_options
      nil, # oauth_access_id
    )

    with_hydro_publisher(GitHub.aqueduct_fallback_hydro_publisher.hydro_publisher) do
      assert_hydro_messages(count: 1, schema: "github.v1.GistPush")
      assert_hydro_published(expected_message, schema: "github.v1.GistPush")
    end
  end

  def reset_timestamp
    time = Time.at(420)
    Gist.where(id: @gist.id).update_all(updated_at: time)
    @gist.reload
    assert_equal time, @gist.updated_at
  end

  def push_job!(path, input = nil, pusher = @pusher.login)
    ENV["GIT_PUSHER"] = pusher if pusher
    input ||= @input
    GistPushJob.perform_now(
      path,
      pusher,
      refs =
        input.split("\n").inject([]) do |list, line|
          before, after, ref = line.split(" ", 3)
          list << [ref, before, after]
        end,
      Time.current,
    )
  end

  def push_test!(path, input = nil)
    push_job!(path, input)
  ensure
    ENV.delete("GIT_PUSHER")
  end

  def anonymous_push_test!(path, input = nil)
    push_job!(path, input, nil)
  end

  def simple_push!
    push_test! @gist.shard_path, [
      GitHub::NULL_OID,
      "251a4d8118d2c9c746c687efceaacac799e67ad9",
      "refs/heads/main"].join(" ")
  end

  def build_input(refs)
    refs.map { |(ref, bef, af)| "#{bef} #{af} #{ref}" }.join("\n")
  end
end
