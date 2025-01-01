# frozen_string_literal: true

require "test_helper"

class AdvisorySyncStateTest < ActiveSupport::TestCase
  test "can be scoped to only those that need processing" do
    queued = create(:advisory_sync_state)
    failed = create(:advisory_sync_state, :failed)
    succeeded = create(:advisory_sync_state, :succeeded)

    assert AdvisorySyncState.unprocessed.include?(queued)
    refute AdvisorySyncState.unprocessed.include?(failed)
    refute AdvisorySyncState.unprocessed.include?(succeeded)
  end

  test "can be scoped to only the stalest" do
    original_limit = AdvisorySyncState::LIMIT
    AdvisorySyncState.const_set(:LIMIT, 4)

    create(:advisory_sync_state) # unprocessed excluded
    create(:advisory_sync_state, :failed, processed_at: 1.day.ago) # recent fail excluded
    medium_fail = create(:advisory_sync_state, :failed, processed_at: 2.days.ago)
    old_fail = create(:advisory_sync_state, :failed, processed_at: 3.days.ago)
    create(:advisory_sync_state, :succeeded, processed_at: 1.day.ago) # recent success excluded
    medium_success = create(:advisory_sync_state, :succeeded, processed_at: 2.days.ago)
    old_success = create(:advisory_sync_state, :succeeded, processed_at: 3.days.ago)

    assert_equal [old_fail, old_success, medium_fail, medium_success], AdvisorySyncState.stale

    AdvisorySyncState.const_set(:LIMIT, original_limit)
  end

  test "provides a batched api to get ids of unprocessed advisories to sync" do
    create_list(:advisory_sync_state, 500, :succeeded) # processed excluded
    queued = create_list(:advisory_sync_state, 1500)

    expected_advisory_ids = queued.map(&:advisory_id)
    processor = mock
    processor.expects(:process).once.with(expected_advisory_ids[0...1000])
    processor.expects(:process).once.with(expected_advisory_ids[1000..])

    AdvisorySyncState.batched_advisory_ids_to_sync(scope: :unprocessed).each do |advisory_ids|
      processor.process(advisory_ids)
    end
  end

  test "provides a batched api to get ids of stale advisories to sync" do
    create_list(:advisory_sync_state, 500) # unprocessed excluded
    old_processed = create_list(:advisory_sync_state, 1500, :succeeded, processed_at: 2.days.ago)
    recent_processed = create_list(:advisory_sync_state, 1500, :succeeded, processed_at: 1.day.ago)

    expected_advisory_ids = old_processed.map(&:advisory_id) + recent_processed.map(&:advisory_id)
    processor = mock
    processor.expects(:process).once.with(expected_advisory_ids[0...1000])
    processor.expects(:process).once.with(expected_advisory_ids[1000...2000])
    processor.expects(:process).once.with(expected_advisory_ids[2000..])

    AdvisorySyncState.batched_advisory_ids_to_sync(scope: :stale).each do |advisory_ids|
      processor.process(advisory_ids)
    end
  end

  test "queueing an advisory to be synced will create or update the sync state" do
    advisory = create(:advisory)

    assert_changes -> { AdvisorySyncState.count }, from: 0, to: 1 do
      AdvisorySyncState.enqueue(advisory)
    end

    assert_nil advisory.sync_state.processed_at
    assert_nil advisory.sync_state.pushed_at

    advisory.sync_state.update(processed_at: Time.current, pushed_at: Time.current)

    refute_nil advisory.sync_state.processed_at
    refute_nil advisory.sync_state.pushed_at

    assert_no_changes -> { AdvisorySyncState.count } do
      AdvisorySyncState.enqueue(advisory)
    end

    advisory.sync_state.reload
    assert_nil advisory.sync_state.processed_at
    assert_nil advisory.sync_state.pushed_at
  end

  test "failure! sets processed but not pushed" do
    state = create(:advisory_sync_state)
    state.failure!
    refute_nil state.processed_at
    assert_nil state.pushed_at
  end

  test "success! sets processed and pushed" do
    state = create(:advisory_sync_state)
    state.success!
    refute_nil state.processed_at
    refute_nil state.pushed_at
  end
end
