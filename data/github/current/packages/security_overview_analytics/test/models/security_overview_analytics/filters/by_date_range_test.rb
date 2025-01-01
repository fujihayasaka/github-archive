# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    class ByDateRangeTest < GitHub::TestCase
      context "#apply" do
        context "table name" do
          test "omits table name by default" do
            assert ByDateRange.new(from: ::Date.today - 1, to: ::Date.today)
              .apply
              .start_with?("id BETWEEN")
          end

          test "uses provided table name" do
            assert ByDateRange.new(from: ::Date.today - 1, to: ::Date.today, table: "MyTable")
              .apply
              .start_with?("MyTable.id BETWEEN")
          end

          test "omits table name when provided a blank value" do
            assert ByDateRange.new(from: ::Date.today - 1, to: ::Date.today, table: nil)
              .apply
              .start_with?("id BETWEEN")

            assert ByDateRange.new(from: ::Date.today - 1, to: ::Date.today, table: "")
              .apply
              .start_with?("id BETWEEN")
          end
        end

        test "raises error when 'max_datapoints' is less than 1" do
          assert_raises(ArgumentError) { ByDateRange.new(from: ::Date.today - 1, to: ::Date.today, max_datapoints: 0) }
          assert_raises(ArgumentError) { ByDateRange.new(from: ::Date.today - 1, to: ::Date.today, max_datapoints: -1) }
          assert ByDateRange.new(from: ::Date.today - 1, to: ::Date.today, max_datapoints: 1)
          assert ByDateRange.new(from: ::Date.today - 1, to: ::Date.today, max_datapoints: 100)
        end

        test "filters by 'to' as the single sample when 'to' and 'from' are the same" do
          to = ::Date.today
          Timecop.freeze to do
            from = to

            expected = ByDateRange::POINTS_TEMPLATE % { date_keys: ::SecurityOverviewAnalytics::Date.id_from_date(to) }
            assert_equal expected, ByDateRange.new(from: from, to: to).apply
            assert_equal expected, ByDateRange.new(from: to, to: from).apply
          end
        end

        test "filters by 'to' as the single sample when 'max_datapoints' is 1" do
          to = ::Date.today
          Timecop.freeze to do
            from = to - 100

            expected = ByDateRange::POINTS_TEMPLATE % { date_keys: ::SecurityOverviewAnalytics::Date.id_from_date(to) }
            assert_equal expected, ByDateRange.new(from: from, to: to, max_datapoints: 1).apply
            assert_equal expected, ByDateRange.new(from: to, to: from, max_datapoints: 1).apply
          end
        end

        test "filters by daily sampling when date range is less than or equal to 'max_datapoints'" do
          to = ::Date.today
          Timecop.freeze to do
            max_datapoints = 10
            max_days_between = max_datapoints - 1
            (1..max_days_between).each do |d|
              from = to - d

              expected = ByDateRange::RANGE_TEMPLATE % {
                start_date_key: ::SecurityOverviewAnalytics::Date.id_from_date(from),
                end_date_key: ::SecurityOverviewAnalytics::Date.id_from_date(to)
              }
              assert_equal expected, ByDateRange.new(from: from, to: to, max_datapoints: max_datapoints).apply
              assert_equal expected, ByDateRange.new(from: to, to: from, max_datapoints: max_datapoints).apply
            end
          end
        end

        test "filters by weekly sampling when date range is greater than 'max_datapoints'" do
          to = ::Date.today
          Timecop.freeze to do
            max_datapoints = 10
            min_days_between = max_datapoints
            max_days_between = 7 * max_datapoints - 1
            days_between = [min_days_between].concat((13..max_days_between).step(7).to_a)

            days_between.each do |d|
              from = to - d

              date_keys = (from..to)
                .select { |date| (to - date).to_i.abs % 7 == 0 }
                .map! { |date| ::SecurityOverviewAnalytics::Date.id_from_date(date) }

              expected = ByDateRange::POINTS_TEMPLATE % { date_keys: date_keys.join(", ") }
              assert_equal ((d + 1) / 7.0).ceil, date_keys.size
              assert_equal expected, ByDateRange.new(from: from, to: to, max_datapoints: max_datapoints).apply
              assert_equal expected, ByDateRange.new(from: to, to: from, max_datapoints: max_datapoints).apply
            end
          end
        end

        test "filters by 'from' and 'to' dates if the weekly sampling would select fewer than 2 samples" do
          to = ::Date.today
          Timecop.freeze to do
            [3, 6].each do |max_datapoints|
              from = to - max_datapoints
              date_keys = [from, to].map! { |date| ::SecurityOverviewAnalytics::Date.id_from_date(date) }
              expected = ByDateRange::POINTS_TEMPLATE % { date_keys: date_keys.join(", ") }
              assert_equal expected, ByDateRange.new(from: from, to: to, max_datapoints: max_datapoints).apply
              assert_equal expected, ByDateRange.new(from: to, to: from, max_datapoints: max_datapoints).apply
            end
          end
        end

        test "filters by monthly sampling when number of weeks in date range is greater than 'max_datapoints'" do
          Timecop.freeze ::Date.today do
            max_datapoints = 3
            [
              [2, ::Date.today.beginning_of_month.prev_month(1), ::Date.today.beginning_of_month],
              [2, ::Date.today.beginning_of_month.prev_month(1), ::Date.today.end_of_month],
              [3, ::Date.today.beginning_of_month.prev_month(2), ::Date.today.beginning_of_month],
              [3, ::Date.today.beginning_of_month.prev_month(2), ::Date.today.end_of_month],
            ].each do |expected_sample_count, from, to|
              date_keys = (from..to)
                .select { |date| date.day == 1 }
                .map! { |date| ::SecurityOverviewAnalytics::Date.id_from_date(date) }

              expected = ByDateRange::POINTS_TEMPLATE % { date_keys: date_keys.join(", ") }
              assert_equal expected_sample_count, date_keys.size
              assert_equal expected, ByDateRange.new(from: from, to: to, max_datapoints: max_datapoints).apply
              assert_equal expected, ByDateRange.new(from: to, to: from, max_datapoints: max_datapoints).apply
            end
          end
        end

        test "filters by 'from' and 'to' dates if the monthly sampling would select fewer than 2 samples" do
          Timecop.freeze ::Date.today do
            max_datapoints = 2
            [
              [::Date.today.beginning_of_month, ::Date.today.end_of_month],
              [::Date.today.end_of_month.prev_month(1), ::Date.today.end_of_month],
              [::Date.today - 7 * max_datapoints, ::Date.today],
            ].each do |from, to|
              date_keys = [from, to].map! { |date| ::SecurityOverviewAnalytics::Date.id_from_date(date) }

              expected = ByDateRange::POINTS_TEMPLATE % { date_keys: date_keys.join(", ") }
              assert_equal expected, ByDateRange.new(from: from, to: to, max_datapoints: max_datapoints).apply
              assert_equal expected, ByDateRange.new(from: to, to: from, max_datapoints: max_datapoints).apply
            end
          end
        end

        test "filters by 'from' and 'to' dates when number of months in date range is greater than 'max_datapoints'" do
          Timecop.freeze ::Date.today do
            max_datapoints = 2
            to = ::Date.today.beginning_of_month + 15 # Choosing middle of a month to prove day is preserved
            from = to.prev_month(max_datapoints + 1).beginning_of_month + 3 # Adding some days just to prove day is preserved

            date_keys = [from, to].map! { |date| ::SecurityOverviewAnalytics::Date.id_from_date(date) }

            expected = ByDateRange::POINTS_TEMPLATE % { date_keys: date_keys.join(", ") }
            assert_equal expected, ByDateRange.new(from: from, to: to, max_datapoints: max_datapoints).apply
            assert_equal expected, ByDateRange.new(from: to, to: from, max_datapoints: max_datapoints).apply
          end
        end
      end
    end
  end
end
