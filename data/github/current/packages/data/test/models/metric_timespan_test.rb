# typed: true
# frozen_string_literal: true

require "test_helper"

class MetricTimespanTest < GitHub::TestCase
  context ".for" do
    test "period defaults to :week" do
      assert_equal MetricTimespan::Week, MetricTimespan.for
    end

    test "invalid period throws exception" do
      assert_raises { MetricTimespan.for(:foo) }
    end

    test "allowed values" do
      assert_equal MetricTimespan::Week, MetricTimespan.for(:week)
      assert_equal MetricTimespan::Month, MetricTimespan.for(:month)
      assert_equal MetricTimespan::Year, MetricTimespan.for(:year)
    end
  end

  context ".beginning" do
    test "defaults to beginning today" do
      freeze_time do
        assert_equal MetricTimespan::Week.new(beginning: Time.zone.today), MetricTimespan::Week.beginning
        assert_equal MetricTimespan::Month.new(beginning: Time.zone.today), MetricTimespan::Month.beginning
        assert_equal MetricTimespan::Year.new(beginning: Time.zone.today), MetricTimespan::Year.beginning
      end
    end
  end

  context ".ending" do
    test "derives beginning from ending" do
      ending = Time.zone.parse "2018-05-02"

      assert_equal MetricTimespan::Week.new(beginning: Time.zone.parse("2018-04-25")), MetricTimespan::Week.ending(ending)
      assert_equal MetricTimespan::Month.new(beginning: Time.zone.parse("2018-04-02")), MetricTimespan::Month.ending(ending)
      assert_equal MetricTimespan::Year.new(beginning: Time.zone.parse("2017-05-01")), MetricTimespan::Year.ending(ending)
    end

    test "defaults to ending today" do
      travel_to Time.zone.parse("2018-05-02") do
        assert_equal MetricTimespan::Week.new(beginning: Time.zone.parse("2018-04-25")), MetricTimespan::Week.ending
        assert_equal MetricTimespan::Month.new(beginning: Time.zone.parse("2018-04-02")), MetricTimespan::Month.ending
        assert_equal MetricTimespan::Year.new(beginning: Time.zone.parse("2017-05-01")), MetricTimespan::Year.ending
      end
    end
  end

  context "#initialize" do
    test "accepts beginning as multiple types" do
      time = Time.zone.parse("2007-10-6")
      week = MetricTimespan::Week.new(beginning: time)

      # Time
      assert_equal time, MetricTimespan::Week.new(beginning: time).to_range.begin

      # Date
      assert_equal week, MetricTimespan::Week.new(beginning: time.to_date)
      # DateTime
      assert_equal week, MetricTimespan::Week.new(beginning: time.to_datetime)
      # String
      assert_equal week, MetricTimespan::Week.new(beginning: "2007-10-06")
      # Numeric
      assert_equal week, MetricTimespan::Week.new(beginning: time.to_i)
    end

    test "beginning defaults to beginning of current period" do
      freeze_time do
        assert_equal MetricTimespan::Week.new(beginning: Time.current.beginning_of_week), MetricTimespan::Week.new
        assert_equal MetricTimespan::Month.new(beginning: Time.current.beginning_of_month), MetricTimespan::Month.new
        assert_equal MetricTimespan::Year.new(beginning: Time.current.beginning_of_year), MetricTimespan::Year.new
      end
    end

    context "when period=year" do
      test "adjusts to the beginning of the week" do
        given_thursday = MetricTimespan::Year.beginning("2018-10-11")
        beginning_monday = MetricTimespan::Year.beginning("2018-10-08")

        assert_equal beginning_monday, given_thursday
      end
    end

    context "ending time" do
      test "is the period duration from beginning time" do
        travel_to Time.zone.parse("2017-07-22") do # year ends on Sunday
          assert_equal Time.current.next_week.beginning_of_week, MetricTimespan::Week.new.to_range.end
          assert_equal Time.current.next_month.beginning_of_month, MetricTimespan::Month.new.to_range.end
          assert_equal Time.current.next_year.beginning_of_year, MetricTimespan::Year.new.to_range.end
        end
      end

      context "when period=year" do
        test "adjusts to the last sunday" do
          ending = "2014-12-31" # year ends on Wednesday
          assert_equal Time.zone.parse("2014-12-29"), MetricTimespan::Year.ending(ending).to_range.end
        end
      end
    end
  end

  test "equals another MetricTimespan by value" do
    assert_equal MetricTimespan::Week.new, MetricTimespan::Week.new
    refute_equal MetricTimespan::Week.new, MetricTimespan::Month.new
    refute_equal MetricTimespan::Week.new, MetricTimespan::Week.beginning("2007-10-06")
  end

  context "#to_range" do
    test "is a range for the timespan's beginning/ending times" do
      range = MetricTimespan::Week.beginning("2007-10-06").to_range

      assert_equal Time.zone.parse("2007-10-06")..Time.zone.parse("2007-10-13"), range
    end
  end

  context "#to_s" do
    test "prints period + beginning suitable for cache key" do
      assert_equal "week:2017-07-17", MetricTimespan::Week.beginning("2017-07-17").to_s
    end
  end

  context "#title" do
    test "is humanized form of beginning/ending of the timespan" do
      assert_equal "Jan 1st to Jan 8th", MetricTimespan::Week.beginning("2018-01-01").title
      assert_equal "Jan 1st to Feb 1st", MetricTimespan::Month.beginning("2018-01-01").title
      assert_equal "Jan 1st, 2018 to Dec 31st, 2018", MetricTimespan::Year.beginning("2018-01-01").title
    end
  end

  context "#buckets" do
    context "for a week" do
      test "have all the days of the week" do
        assert_equal 7, MetricTimespan::Week.new.buckets.length
      end
    end

    context "for a month" do
      test "have all the days of the month" do
        assert_equal 31, MetricTimespan::Month.beginning("2018-01-01").buckets.count
        assert_equal 30, MetricTimespan::Month.beginning("2018-04-01").buckets.count
        assert_equal 28, MetricTimespan::Month.beginning("2018-02-01").buckets.count
        assert_equal 29, MetricTimespan::Month.beginning("2004-02-01").buckets.count
      end
    end

    context "for a year" do
      test "have all the weeks of the year" do
        travel_to Time.zone.parse("2021-09-09") do
          assert_equal 52, MetricTimespan::Year.new.buckets.count
        end
      end
    end
  end

  context "#previous" do
    context "week" do
      test "returns a new timespan for the prior week" do
        current = Time.zone.parse("2018-08-28")
        previous = Time.zone.parse("2018-08-21")

        assert_equal MetricTimespan::Week.beginning(previous),
          MetricTimespan::Week.beginning(current).previous
      end
    end
  end

  context "#next" do
    context "week" do
      test "returns a new timespan for the next week" do
        current = Time.zone.parse("2018-08-28")
        after = Time.zone.parse("2018-09-04")

        assert_equal MetricTimespan::Week.beginning(after),
          MetricTimespan::Week.beginning(current).next
      end
    end
  end
end
