# typed: false
# frozen_string_literal: true

require "test_helper"

class JobStatusTest < GitHub::TestCase
  setup do
    GitHub.cache.allow = /.*/
    GitHub.cache.clear
    @incomplete_job_ttl_lower_bound = JobStatus::DEFAULT_OVERALL_TTL - 5.minutes
    @completed_job_ttl_upper_bound = JobStatus::DEFAULT_COMPLETED_JOB_TTL + 5.minutes
  end

  test "initializes with default id, state, and ttl" do
    status = JobStatus.new
    assert_equal "pending", status.state
    assert_equal 36, status.id.length
    assert_equal JobStatus::DEFAULT_OVERALL_TTL, status.ttl
    assert status.pending?
  end

  test "initializes with state, id, and ttl" do
    status = JobStatus.new(state: "started", id: 42, ttl: 5)
    assert_equal "started", status.state
    assert_equal 42, status.id
    assert_equal 5, status.ttl
    assert status.started?
  end

  test "only accepts valid states" do
    assert_raises(RuntimeError) do
      JobStatus.new(state: "bogus")
    end
  end

  test "moves to the started state" do
    status = JobStatus.new
    refute status.started?
    status.started!
    assert status.started?
  end

  test "saves with expected ttl" do
    Timecop.freeze do
      status = JobStatus.new(ttl: 5.minutes)
      # rubocop:todo GitHub/DoNotUseGlobalKv
      GitHub.kv.expects(:set).with(anything, status.to_json, expires: 5.minutes.from_now)
      # rubocop:enable GitHub/DoNotUseGlobalKv
      status.save
    end
  end

  test "invalid ttl defaults to DEFAULT_OVERALL_TTL" do
    assert_raises(ArgumentError) { JobStatus.new(ttl: "foo") }
    assert_raises(TypeError) { JobStatus.new(ttl: nil) }
  end

  test "ttl propagates from one instance to another" do
    now = Time.now

    status = JobStatus.new(ttl: 7.minutes)

    Timecop.freeze(now) do
      status.save
    end

    Timecop.freeze(now + 2.minutes) do
      status = JobStatus.find!(status.id)
      assert_equal 7.minutes, status.ttl

      # ttl should still be 7 minutes from now, even though a minute has passed
      GitHub.kv.expects(:set).with(anything, anything, expires: now + 9.minutes) # rubocop:todo GitHub/DoNotUseGlobalKv
      status.started!
    end
  end

  test "moves to the queued state" do
    status = JobStatus.new
    refute status.queued?
    refute status.finished?
    status.queued!
    assert status.queued?
    refute status.finished?
  end

  test "moves to the success state" do
    Timecop.freeze do
      status = JobStatus.create
      cache_key = status.send(:cache_key)

      refute status.success?
      refute status.finished?
      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert GitHub.kv.ttl(cache_key).value!.to_i > (Time.now + @incomplete_job_ttl_lower_bound).to_i
      # rubocop:enable GitHub/DoNotUseGlobalKv

      status.success!

      assert status.success?
      assert status.finished?
      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert GitHub.kv.ttl(cache_key).value!.to_i < (Time.now + @completed_job_ttl_upper_bound).to_i
      # rubocop:enable GitHub/DoNotUseGlobalKv
    end
  end

  test "moves to the error state" do
    status = JobStatus.create
    cache_key = status.send(:cache_key)

    refute status.error?
    refute status.finished?
    # rubocop:todo GitHub/DoNotUseGlobalKv
    assert GitHub.kv.ttl(cache_key).value!.to_i > (Time.now + @incomplete_job_ttl_lower_bound).to_i
    # rubocop:enable GitHub/DoNotUseGlobalKv

    status.error!

    assert status.error?
    assert status.finished?
    # rubocop:todo GitHub/DoNotUseGlobalKv
    assert GitHub.kv.ttl(cache_key).value!.to_i < (Time.now + @completed_job_ttl_upper_bound).to_i
    # rubocop:enable GitHub/DoNotUseGlobalKv
  end

  test "accepts an optional message when moving to error state" do
    status = JobStatus.new
    refute status.error?
    refute status.finished?
    status.error!("boom")
    assert status.error?
    assert status.finished?
    assert_equal "boom", status.error_message
  end

  test "generates json hash representation" do
    status = JobStatus.new
    hash = status.as_json
    assert_equal hash[:id], status.id
    assert_equal hash[:state], "pending"
    assert_equal hash[:ttl], status.ttl
  end

  test "generates json representation" do
    status = JobStatus.new
    hash = JSON.parse(status.to_json)
    assert_equal hash["id"], status.id
    assert_equal hash["state"], "pending"
  end

  test "tracks successful jobs" do
    value = nil

    status = JobStatus.new
    status.track do
      value = 42
    end

    assert_equal 42, value
    assert status.success?
  end

  test "tracks failed jobs" do
    value = nil

    status = JobStatus.new
    assert_raises(RuntimeError) do
      status.track do
        raise "boom"
        value = 42 # rubocop:disable Lint/UnreachableCode
      end
    end
    assert_nil value
    assert status.error?
    assert_equal "boom", status.error_message
  end

  test "returns nil for missing job id" do
    assert_nil JobStatus.find(42)
  end

  test "bang raises error for missing job id" do
    assert_raises(JobStatus::NotFound) do
      JobStatus.find!(42)
    end
  end

  test "finds job by id" do
    status = JobStatus.new
    status.save
    found = JobStatus.find(status.id)
    refute_nil found
    assert_equal status.id, found.id
  end

  test "finding job with blank id returns empty result" do
    assert_nil JobStatus.find(nil), "expected empty result"
  end

  test "bang finds job by id" do
    status = JobStatus.new
    status.save
    refute_nil JobStatus.find!(status.id)
  end

  test "find multiple jobs by ids" do
    statuses = [JobStatus.new]
    statuses << JobStatus.new
    statuses.map(&:save)
    found = JobStatus.find_many(statuses.map(&:id))
    refute_empty found
    assert_equal statuses.map(&:id), found.map(&:id)
  end

  test "finding multiple jobs with empty list returns empty result" do
    assert_empty JobStatus.find_many([]), "expected empty result"
  end

  test "returns empty array for missing job ids" do
    status = JobStatus.new
    status.save
    found = JobStatus.find_many(["some_id"])
    assert_equal [nil], found
  end

  test "find multiple jobs by prefix" do
    statuses = [
      JobStatus.new(id: "foo:bar"),
      JobStatus.new(id: "foo:baz"),
      JobStatus.new(id: "foo:qux"),
    ]
    statuses.map(&:save)
    found = JobStatus.find_prefix("foo")
    refute_empty found
    assert_equal statuses.map(&:id), found.map(&:id)
  end

  test "removes job from memcache on destroy" do
    status = JobStatus.new
    status.save
    refute_nil JobStatus.find(status.id)
    status.destroy
    assert_nil JobStatus.find(status.id)
  end

  test "creates and saves status with default attributes" do
    status = JobStatus.create
    found = JobStatus.find(status.id)
    assert found.pending?
  end

  test "creates and saves status with custom attributes" do
    status = JobStatus.create(state: "success")
    found = JobStatus.find(status.id)
    assert found.success?
  end

  test "works when we have a read-only DB connection" do
    ActiveRecord::Base.connected_to(role: :reading) do
      value = nil

      status = JobStatus.new
      status.track do
        value = 42
      end

      assert status.success?
      assert_equal 42, value
    end
  end

  test "init works from json" do
    status = JobStatus.new(state: "success")
    status.save
    found = JobStatus.find(status.id)
    assert found.success?
  end
end
