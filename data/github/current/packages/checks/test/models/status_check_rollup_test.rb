# typed: true
# frozen_string_literal: true

require "test_helper"

class StatusCheckRollupTest < GitHub::TestCase
  FakeStatusCheck = Struct.new(:state, :state_changed_at)

  def test_status_checks
    rollup = StatusCheckRollup.new(status_checks: [FakeStatusCheck.new])
    assert_equal 1, rollup.status_checks.count
  end

  def test_pending_if_no_items
    rollup = StatusCheckRollup.new(status_checks: [])
    assert_equal "pending", rollup.state
  end

  def test_pending_if_something_is_pending_and_nothing_is_failing
    status_checks = [
      FakeStatusCheck.new("pending"),
      FakeStatusCheck.new("success"),
    ]
    rollup = StatusCheckRollup.new(status_checks: status_checks)
    assert_equal "pending", rollup.state
  end

  def test_pending_if_something_is_queued_and_nothing_is_failing
    status_checks = [
      FakeStatusCheck.new("queued"),
      FakeStatusCheck.new("success"),
    ]
    rollup = StatusCheckRollup.new(status_checks: status_checks)
    assert_equal "pending", rollup.state
  end

  def test_pending_if_something_is_in_progress_and_nothing_is_failing
    status_checks = [
      FakeStatusCheck.new("in_progress"),
      FakeStatusCheck.new("success"),
    ]
    rollup = StatusCheckRollup.new(status_checks: status_checks)
    assert_equal "pending", rollup.state
  end

  def test_failure_if_anything_is_failure
    status_checks = [
      FakeStatusCheck.new("pending"),
      FakeStatusCheck.new("success"),
      FakeStatusCheck.new("failure"),
    ]
    rollup = StatusCheckRollup.new(status_checks: status_checks)
    assert_equal "failure", rollup.state
  end

  def test_failure_if_anything_is_error
    status_checks = [
      FakeStatusCheck.new("pending"),
      FakeStatusCheck.new("success"),
      FakeStatusCheck.new("error"),
    ]
    rollup = StatusCheckRollup.new(status_checks: status_checks)
    assert_equal "failure", rollup.state
  end

  def test_failure_if_anything_is_cancelled
    status_checks = [
      FakeStatusCheck.new("pending"),
      FakeStatusCheck.new("success"),
      FakeStatusCheck.new("cancelled"),
    ]
    rollup = StatusCheckRollup.new(status_checks: status_checks)
    assert_equal "failure", rollup.state
  end

  def test_failure_if_anything_is_action_required
    status_checks = [
      FakeStatusCheck.new("pending"),
      FakeStatusCheck.new("success"),
      FakeStatusCheck.new("action_required"),
    ]
    rollup = StatusCheckRollup.new(status_checks: status_checks)
    assert_equal "failure", rollup.state
  end

  def test_failure_if_anything_is_timed_out
    status_checks = [
      FakeStatusCheck.new("pending"),
      FakeStatusCheck.new("success"),
      FakeStatusCheck.new("timed_out"),
    ]
    rollup = StatusCheckRollup.new(status_checks: status_checks)
    assert_equal "failure", rollup.state
  end

  def test_failure_if_anything_is_stale
    status_checks = [
      FakeStatusCheck.new("pending"),
      FakeStatusCheck.new("success"),
      FakeStatusCheck.new("stale"),
    ]
    rollup = StatusCheckRollup.new(status_checks: status_checks)
    assert_equal "failure", rollup.state
  end

  def test_success_if_everything_is_a_success
    status_checks = [
      FakeStatusCheck.new("success"),
      FakeStatusCheck.new("success"),
    ]
    rollup = StatusCheckRollup.new(status_checks: status_checks)
    assert_equal "success", rollup.state
  end

  def test_success_if_everything_is_a_success_or_neutral_or_skipped
    status_checks = [
      FakeStatusCheck.new("success"),
      FakeStatusCheck.new("neutral"),
      FakeStatusCheck.new("skipped"),
    ]
    rollup = StatusCheckRollup.new(status_checks: status_checks)
    assert_equal "success", rollup.state
  end

  def test_success_if_everything_is_neutral
    status_checks = [
      FakeStatusCheck.new("neutral"),
      FakeStatusCheck.new("neutral"),
    ]
    rollup = StatusCheckRollup.new(status_checks: status_checks)
    assert_equal "success", rollup.state
  end

  def test_success_if_everything_is_skipped
    status_checks = [
      FakeStatusCheck.new("skipped"),
      FakeStatusCheck.new("skipped"),
    ]
    rollup = StatusCheckRollup.new(status_checks: status_checks)
    assert_equal "success", rollup.state
  end

  def test_updated_at_is_most_recent
    thing1 = FakeStatusCheck.new("success", Time.now - 10)
    thing2 = FakeStatusCheck.new("success", Time.now)
    rollup = StatusCheckRollup.new(status_checks: [thing1, thing2])
    assert_equal thing2.state_changed_at, rollup.updated_at
  end
end
