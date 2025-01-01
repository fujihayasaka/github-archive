# typed: true
# frozen_string_literal: true

require "test_helper"

class MetricCountsTest < GitHub::TestCase
  def counts_hash
    { 1 => 5, 2 => 7, 3 => 0 }
  end

  test "calculates total across counts" do
    assert_equal 12, MetricCounts.new(counts_hash).total
  end

  test "calculates max across counts" do
    assert_equal 7, MetricCounts.new(counts_hash).max
  end

  test "calculates total change between two counts" do
    counts = MetricCounts.new(counts_hash)
    other = MetricCounts.new(4 => 3, 5 => 5, 6 => 2)

    assert_equal 2, counts.total_change_from(other)
    assert_equal -2, other.total_change_from(counts)
  end

  test "calculates percentage change between two counts" do
    counts = MetricCounts.new(counts_hash)
    other = MetricCounts.new(4 => 3, 5 => 5, 6 => 2)

    assert_equal 20, counts.percent_change_from(other)
    assert_equal -16, other.percent_change_from(counts)
  end

  test "can be enumerated" do
    assert_kind_of Enumerable, MetricCounts.new
    assert_instance_of Enumerator, MetricCounts.new.each
    assert_equal 3, MetricCounts.new(counts_hash).count
  end

  test "serializes to JSON" do
    assert_equal '[["1",5],["2",7],["3",0]]', MetricCounts.new(counts_hash).to_json
  end

  test "can deserialize from JSON" do
    assert_equal(
      MetricCounts.new(counts_hash),
      MetricCounts.from_json('{ "1": 5, "2": 7, "3": 0 }'),
    )
  end

  test "can round-trip as JSON" do
    counts = MetricCounts.new(counts_hash)
    assert_equal counts, MetricCounts.from_json(counts.to_json)
  end

  test "zeroes out buckets" do
    assert_equal MetricCounts.new(counts_hash),
      MetricCounts.new({ 1 => 5, 2 => 7 }, [3])
  end

  context "#historical" do
    test "truncates future counts" do
      travel_to Time.zone.parse("2017-07-18 07:00") do
        counts = MetricCounts.new({}, MetricTimespan::Week.new.buckets)

        assert_equal 2, counts.historical.count
      end
    end

    test "truncates counts beyond a given date" do
      travel_to Time.zone.parse("2017-07-17 07:00") do
        counts = MetricCounts.new({}, MetricTimespan::Week.new.buckets)

        assert_equal 2, counts.historical(Time.zone.parse("2017-07-18 07:00")).count
      end
    end

    test "truncates counts starting precisely at the date" do
      travel_to Time.zone.parse("2017-07-17 07:00") do
        counts = MetricCounts.new({}, MetricTimespan::Week.new.buckets)

        assert_equal 0, counts.historical(Time.zone.parse("2017-07-17 00:00:00")).count
        assert_equal 1, counts.historical(Time.zone.parse("2017-07-17 00:00:01")).count
      end
    end
  end
end
