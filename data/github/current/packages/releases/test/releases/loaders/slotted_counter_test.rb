# typed: true
# frozen_string_literal: true

require "test_helper"

class Releases::Loaders::SlottedCounterTest < Api::TestCase
  setup do
    SlottedCounterService.increment_type_and_id("FooType", 4)
    SlottedCounterService.increment_type_and_id("FooType", 4)
    SlottedCounterService.increment_type_and_id("FooType", 5)
    SlottedCounterService.increment_type_and_id("BarType", 4)
  end

  test "returns 0 when there is no count" do
    assert_equal 0, Releases::Loaders::SlottedCounter.load("NewType", 55).sync
    assert_equal 0, Releases::Loaders::SlottedCounter.load("FooType", 3).sync
  end

  test "returns the sum for the record type and id" do
    assert_equal 2, Releases::Loaders::SlottedCounter.load("FooType", 4).sync
  end

  test "returns correct results even in batches" do
    counts = Promise.all([
      Releases::Loaders::SlottedCounter.load("FooType", 4),
      Releases::Loaders::SlottedCounter.load("FooType", 5)
    ]).sync
    assert_equal [2, 1], counts
  end
end
