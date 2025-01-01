# typed: true
# frozen_string_literal: true

require "test_helper"

class SlottedCounterServiceTest < GitHub::TestCase
  fixtures do
    @repo = create :repository, from_example: :repository_test_simple
  end

  setup do
    @release = create :release, repository: @repo, author: @repo.owner, tag_name: "v1"
    @record = create :release_asset, release: @release, uploader: @repo.owner
  end

  test "#count works when there are no rows for record" do
    assert_equal 0, SlottedCounterService.count(@record)
  end

  test "#count_type_and_id works when there are now rows for record" do
    assert_equal 0, SlottedCounterService.count_type_and_id(@record.class.base_class.name, @record.id)
  end

  test "#increment" do
    assert_equal 0, SlottedCounterService.count(@record)
    assert SlottedCounterService.increment(@record)
    assert_equal 1, SlottedCounterService.count(@record)
    5.times do
      assert SlottedCounterService.increment(@record)
    end
    assert_equal 6, SlottedCounterService.count(@record)
  end

  test "#increment_type_and_id" do
    assert_equal 0, SlottedCounterService.count(@record)
    assert SlottedCounterService.increment_type_and_id(@record.class.base_class.name, @record.id)
    assert_equal 1, SlottedCounterService.count(@record)
    5.times do
      assert SlottedCounterService.increment_type_and_id(@record.class.base_class.name, @record.id)
    end
    assert_equal 6, SlottedCounterService.count(@record)
  end

  test "#increment_type_and_id with increment arg" do
    assert_equal 0, SlottedCounterService.count(@record)
    assert SlottedCounterService.increment_type_and_id(@record.class.base_class.name, @record.id, 2)
    assert_equal 2, SlottedCounterService.count(@record)
    5.times do
      assert SlottedCounterService.increment_type_and_id(@record.class.base_class.name, @record.id, 2)
    end
    assert_equal 12, SlottedCounterService.count(@record)
  end

  test "#increment_type_and_id with increment arg (safety check in case we have a string from Redis)" do
    assert_equal 0, SlottedCounterService.count(@record)
    assert SlottedCounterService.increment_type_and_id(@record.class.base_class.name, @record.id, "2")
    assert_equal 2, SlottedCounterService.count(@record)
    5.times do
      assert SlottedCounterService.increment_type_and_id(@record.class.base_class.name, @record.id, "2")
    end
    assert_equal 12, SlottedCounterService.count(@record)
  end

  test "#increment_aggregated_async once" do
    assert_equal 0, SlottedCounterService.count(@record)

    # act
    Timecop.freeze do
      SlottedCounterService.increment_aggregated_async(@record)
    end
    perform_enqueued_jobs only: SlottedCounterIncrementAggregatedJob

    assert_enqueued_jobs 0, only: SlottedCounterIncrementAggregatedJob
    assert_performed_jobs 1, only: SlottedCounterIncrementAggregatedJob
    assert_equal 1, SlottedCounterService.count(@record)
  end

  test "#increment_aggregated_async more than once" do
    assert_equal 0, SlottedCounterService.count(@record)

    # act
    Timecop.freeze do
      5.times { SlottedCounterService.increment_aggregated_async(@record) }
    end

    assert_enqueued_jobs 1, only: SlottedCounterIncrementAggregatedJob # Should only allow to enqueue once
    perform_enqueued_jobs only: SlottedCounterIncrementAggregatedJob

    assert_enqueued_jobs 0, only: SlottedCounterIncrementAggregatedJob
    assert_performed_jobs 1, only: SlottedCounterIncrementAggregatedJob  # Should only perform one job
    assert_equal 5, SlottedCounterService.count(@record)
  end

  test "#prefill" do
    records = 4.times.map { |i| create :release_asset, release: @release, uploader: @repo.owner, name: "#{i}.zip" }
    record1, record2, record3, record4 = records

    SlottedCounterService.increment(record1)
    2.times { SlottedCounterService.increment(record2) }
    3.times { SlottedCounterService.increment(record3) }
    4.times { SlottedCounterService.increment(record4) }

    SlottedCounterService.prefill(records)
    SlottedCounterService.expects(:count).never

    assert_equal 1, record1.slotted_count
    assert_equal 2, record2.slotted_count
    assert_equal 3, record3.slotted_count
    assert_equal 4, record4.slotted_count
  end

  test "Countable#slotted_count! in enterprise runtime does sync write", enterprise_only: true do
    assert_equal 0, SlottedCounterService.count(@record)
    @record.slotted_count!(:hits)
    assert_equal 1, SlottedCounterService.count(@record)
  end

  test "Countable#slotted_count! enqueues increment aggregated job", skip_enterprise: true do
    assert_equal 0, SlottedCounterService.count(@record)

    assert_enqueued_with(job: SlottedCounterIncrementAggregatedJob, at: 10.minutes.from_now + 10.seconds) do
      @record.slotted_count!(:hits)
    end

    assert_enqueued_jobs 1, only: SlottedCounterIncrementAggregatedJob, queue: :slotted_counters
  end
end
