# typed: true
# frozen_string_literal: true

require "test_helper"

class GistMaintenanceTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @contents = [{ name: "1", value: "random content" }]
    @gist = GistHelpers.generate \
      contents: @contents, user: @owner, description: "my gist"
    @priv = @gist.fork(create(:user))

    @gists = [@gist, @priv] + Array.new(3) do
      GistHelpers.generate contents: @contents, user: create(:user)
    end

    @min_age = 1.day.freeze

    # make all gists eligible for maintenance in the old generation
    @gists.each_with_index do |gist, i|
      gist.update_column :last_maintenance_at, 2.days.ago + (i * 10)
      gist.update_column :pushed_count_since_maintenance,  1
    end
  end

  setup do
    # fixture models in arrays are not reloaded automatically
    @gists.map! { |n| Gist.find(n.id) }
    @spawn_res_ok =     { "argv" => ["foo"], "out" => "", "ok" => true, "status" => 0, "err" => "sync: 92800494.git: +64K\nRunning git-repack" }
    @spawn_res_locked = { "argv" => ["foo"], "out" => "", "ok" => false, "status" => 2, "err" => "fatal: could not get the nw-sync lock. sync already in progress." }
  end

  test "find_longest_time_since_last_maintenance scheduling never maintained gists" do
    @gists.each_with_index do |gist, index|
      gist.update_column(:last_maintenance_at, (index + 2).days.ago)
    end

    gists = Gist.find_longest_time_since_last_maintenance(@gists.size, @min_age)
    assert_same_elements @gists.map(&:id), gists.map(&:id)
  end

  test "find_longest_time_since_last_maintenance excluding fully maintained gists" do
    @gist.update_attribute :last_maintenance_at, 2.days.ago
    @gist.update_attribute :pushed_count_since_maintenance, 0

    gists = Gist.find_longest_time_since_last_maintenance(@gists.size, @min_age)
    assert !gists.include?(@gist)
    assert gists.include?(@gists.last)
  end

  test "find_longest_time_since_last_maintenance orders ifnull(last_maintenance_at, created_at)" do
    @gists[-2].update! last_maintenance_at: 10.days.ago, pushed_count_since_maintenance: 10
    @gists[-3].update! last_maintenance_at: 5.days.ago, pushed_count_since_maintenance: 10
    @gists[-1].update! last_maintenance_at: 3.days.ago,  pushed_count_since_maintenance: 10

    gists = Gist.find_longest_time_since_last_maintenance(@gists.size, @min_age)
    assert_same_elements @gists, gists
  end

  test "find_longest_time_since_last_maintenance excluding failed, scheduled, running gists" do
    @gists[0].update! maintenance_status: "scheduled"
    @gists[1].update! maintenance_status: "running"
    @gists[2].update! maintenance_status: "failed"
    @gists[3].update! maintenance_status: "complete"

    gists = Gist.find_longest_time_since_last_maintenance(@gists.size, @min_age)
    assert_equal 2, gists.size
    assert_equal @gists[3], gists[0]
    assert_equal @gists[4], gists[1]
  end

  test "find_longest_time_since_last_maintenance ignores :scheduled if stale" do
    @gists[0].update! maintenance_status: "scheduled", last_maintenance_attempted_at: Time.now - 2.days
    @gists[1].update! maintenance_status: "running"
    @gists[2].update! maintenance_status: "failed"
    @gists[3].update! maintenance_status: "complete"

    gists = Gist.find_longest_time_since_last_maintenance(@gists.size, @min_age)
    assert_same_elements [@gists[3], @gists[4]], gists
  end

  test "find_most_active_since_last_maintenance triggered by push count and excluding non active gists" do
    @gists[0].update! pushed_count_since_maintenance: 1000
    @gists[1].update! pushed_count_since_maintenance: 500
    @gists[2].update! pushed_count_since_maintenance: 10

    gists = Gist.find_most_active_since_last_maintenance(@gists.size, 20)
    assert_equal 2, gists.size
    assert_equal @gists[0], gists[0]
    assert_equal @gists[1], gists[1]
  end

  test "move_stuck_networks_to_retry! moves as expected" do
    @gists[0].update! maintenance_status: "scheduled", last_maintenance_attempted_at: Time.now - 2.days
    @gists[1].update! maintenance_status: "scheduled", last_maintenance_attempted_at: Time.now
    @gists[2].update! maintenance_status: "failed"
    @gists[3].update! maintenance_status: "complete"

    ngists = RepositoryNetwork.move_stuck_networks_to_retry!(Gist)
    expected = [@gists[0].clone.tap { |g| g.maintenance_status = "retry" }]
    assert_equal 1, ngists
    assert_same_elements expected, Gist.where(maintenance_status: :retry)
  end

  test "updating maintenance_status" do
    assert_raises ActiveRecord::RecordInvalid do
      @gist.update_status(:nope)
    end

    @gist.update_status(:scheduled)
    assert_equal "scheduled", @gist.maintenance_status

    @gist.update_status(:running)
    assert_equal "running", @gist.maintenance_status

    @gist.update_status(:complete)
    assert_equal "complete", @gist.maintenance_status

    @gist.update_status(:failed)
    assert_equal "failed", @gist.maintenance_status

    @gist.maintenance_status = nil
    @gist.save!
  end

  test "updating maintenance_status does not mess with updated_at" do
    timestamp = Time.zone.parse "2016-01-01 17:00:00"
    @gist.update_column :updated_at, timestamp

    assert Gist.record_timestamps, "Expect Gist to record timestamps"

    @gist.update_status(:running)
    assert_equal timestamp, @gist.reload.updated_at, "expected update_status to not mess with updated_at"

    @gist.update_status(:complete, last_maintenance_at: Time.zone.now)
    assert_equal timestamp, @gist.reload.updated_at, "expected update_status to not mess with updated_at"

    assert Gist.record_timestamps, "Expect Gist to still record timestamps"
  end

  test "modified_since_last_maintenance" do
    assert @gist.last_maintenance_at
    assert_equal @gists.size, @gist.gists_modified_since_last_maintenance.size

    @gist.update_attribute(:last_maintenance_at, 1.day.ago)
    @gist.reload
    @gists.each do |gist|
      gist.update_attribute(:pushed_at, 2.days.ago)
      gist.reload
    end

    assert_equal [], @gist.gists_modified_since_last_maintenance

    @gist.update_attribute(:pushed_at, 1.hour.ago)
    @priv.update_attribute(:pushed_at, 1.minute.ago)
    assert_equal [@gist, @priv], @gist.gists_modified_since_last_maintenance

    @gist.update_attribute(:pushed_at, @gist.last_maintenance_at)
    assert_equal [@gist, @priv], @gist.gists_modified_since_last_maintenance
  end

  test "schedule_maintenance" do
    assert_enqueued_jobs 1, queue: @gist.maintenance_queue_name.value! do
      @gist.schedule_maintenance
    end
    @gist.reload
    assert_equal "scheduled", @gist.maintenance_status
  end

  test "doesn't schedule maintenance if last run is too recent" do
    @gist.update_column :pushed_count_since_maintenance, 0
    @gist.update_column :last_maintenance_at, 1.day.ago

    # Reload to deal with DST.
    # If `1.day.ago` is in the repeated 1am-2am hour when DST ends in
    # November, then writing as a DATETIME and reloading it is ambiguous
    # and can change the value of the AR `last_maintenance_at` attribute.
    # For example, 01:20-0800 can turn into 01:20-0700, which is an hour
    # earlier, and the `assert_equal` below will fail.
    # So reload it before we save a copy in `last_run_before`.
    @gist.reload

    last_run_before = @gist.last_maintenance_at
    Gist.schedule_maintenance(@gists.size)
    @gist.reload

    refute_equal "scheduled", @gist.maintenance_status
    assert_equal @gist.last_maintenance_at.to_i, last_run_before.to_i
  end

  test "creating a gist sets last maintenance to created_at" do
    Timecop.freeze do
      gist = GistHelpers.generate \
        contents: @contents, user: @owner, description: "gist_last_maintenance_timestamp"
      assert_equal gist.created_at, gist.last_maintenance_at
      assert_equal "complete", gist.maintenance_status
    end
  end

  test "running maintenance is retried when one backend is locked" do
    assert_equal "complete", @gist.attributes["maintenance_status"]
    ::GitRPC::Backend.any_instance.stubs(:nw_repack).returns(@spawn_res_locked, @spawn_res_ok, @spawn_res_locked, @spawn_res_ok, @spawn_res_locked, @spawn_res_ok)
    @gist.perform_maintenance
    assert_equal "retry", @gist.attributes["maintenance_status"]
  end

  test "running maintenance is retried on spurious failures" do
    assert_equal "complete", @gist.attributes["maintenance_status"]
    ::GitRPC::Backend.any_instance.stubs(:nw_repack).raises(::GitRPC::Error)
    assert_raises(::GitRPC::Error) do
      @gist.perform_maintenance
    end
    assert_equal "spurious_failure", @gist.attributes["maintenance_status"]
  end

  test "running maintenance with spurious errors will mark it failed if we fail more than four times" do
    assert_equal "complete", @gist.attributes["maintenance_status"]
    ::GitRPC::Backend.any_instance.stubs(:nw_repack).raises(::GitRPC::Error)
    assert_raises(::GitRPC::Error) do
      @gist.perform_maintenance
    end
    4.times do
      assert_equal "spurious_failure", @gist.attributes["maintenance_status"]
      assert_raises(::GitRPC::Error) do
        @gist.perform_maintenance("spurious_failure")
      end
    end
    assert_equal "failed", @gist.attributes["maintenance_status"]
  end

  test "gist with corruption that we can't fix is marked as spurious failure" do
    assert_equal "complete", @gist.attributes["maintenance_status"]
    ::GitRPC::Backend.any_instance.stubs(:nw_repack).raises(::GitRPC::Error)
    ::GitRPC::Backend.any_instance.stubs(:nw_fsck).returns({ ok: false }.stringify_keys).then.returns({ ok: true }.stringify_keys)
    ::GitRPC::Backend.any_instance.stubs(:restore_objects)
      .returns({ ok: false, status: 1 }.stringify_keys)
      .then.returns({ ok: true, status: 0 }.stringify_keys)
    assert_raises(::GitRPC::Error) do
      @gist.perform_maintenance
    end
    assert_equal "spurious_failure", @gist.attributes["maintenance_status"]
  end

  test "maintenance on repository repository with fixed corruption will be retried" do
    assert_equal "complete", @gist.attributes["maintenance_status"]
    ::GitRPC::Backend.any_instance.stubs(:nw_repack).raises(::GitRPC::Error)
    ::GitRPC::Backend.any_instance.stubs(:nw_fsck).returns({ ok: false }.stringify_keys)
    ::GitRPC::Backend.any_instance.stubs(:restore_objects).returns({ ok: true, err: "1 object was restored" }.stringify_keys)
    @gist.perform_maintenance
    assert_equal "retry", @gist.attributes["maintenance_status"]
  end

  context "maintenance_disabled?" do
    test "is true when the maint status is broken" do
      refute_equal "broken", @gist.maintenance_status
      refute @gist.maintenance_disabled?

      @gist.mark_as_broken

      assert_equal "broken", @gist.maintenance_status
      assert @gist.maintenance_disabled?
    end
  end
end
