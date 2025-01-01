# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class DeleteExpiredNotificationsKeyValuesJobTest < GitHub::TestCase
  include JobTestHelper

  setup do
    @stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(@stats)

    cfg = GitHub::KV::Config.new
    cfg.table_name = :notification_key_values
    cfg.use_local_time = true
    @kv = GitHub::KV.new(config: cfg) { ApplicationRecord::Domain::Notifications.connection }
  end

  def run_cleanup(when_run)
    Timecop.freeze(when_run) do
      DeleteExpiredNotificationsKeyValuesJob.perform_now
    end
  end

  test "deletes expired entries only" do
    @kv.set("foo", "bar", expires: 5.minutes.from_now.utc)
    @kv.set("foo2", "bar", expires: 5.minutes.from_now.utc)
    @kv.set("foo3", "bar", expires: 5.hours.from_now.utc)

    run_cleanup(10.minutes.from_now.utc)

    assert !@kv.exists("foo").value { true }
    assert !@kv.exists("foo2").value { true }
    assert @kv.exists("foo3").value { false }, "key 'foo3' should not have been deleted"
  end
end
