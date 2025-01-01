# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class DateHelperTest < GitHub::TestCase
          fixtures do
            @biz = create(:business)
            @org = create(:organization, business: @biz)
            @repo = create(:private_repository, owner: @org)
          end

          context ".interval_date_ids" do
            context "when end date is before start date" do
              test "it returns an empty array" do
                start_date = ::Date.new(2023, 10, 10)
                end_date = ::Date.new(2023, 10, 1) # End date before start date

                assert_empty(DateHelper.interval_date_ids(start_date, end_date))
              end
            end

            context "when the start and end dates are the same day" do
              test "it returns that date ID" do
                start_date = ::Date.new(2023, 10, 2)
                end_date = start_date
                expected_ids = [20231002]

                assert_equal(expected_ids, DateHelper.interval_date_ids(start_date, end_date))
              end
            end

            context "when the start and end dates are less than 1 week apart" do
              test "it returns date IDs for every in between date" do
                start_date = ::Date.new(2023, 10, 2)
                end_date = start_date + 1
                expected_ids = [20231002, 20231003]

                assert_equal(expected_ids, DateHelper.interval_date_ids(start_date, end_date))
              end
            end

            context "when the start and end dates are more than 8 days apart" do
              test "it returns 8 date IDs" do
                start_date = ::Date.new(2023, 10, 1)
                end_date = start_date + 10
                expected_ids = [20231001, 20231002, 20231003, 20231004, 20231005, 20231007, 20231009, 20231011]

                assert_equal(expected_ids, DateHelper.interval_date_ids(start_date, end_date))
              end
            end

            context "when days in the final week don't align with a week boundary" do
              test "the later intervals are longer" do
                start_date = ::Date.new(2023, 10, 1)
                end_date = ::Date.new(2023, 10, 17) # 2 weeks and 3 days.
                expected_ids = [
                  20231001,
                  20231003,
                  20231005,
                  20231007,
                  20231009,
                  20231011,
                  20231014,
                  20231017
                ]

                assert_equal(expected_ids, DateHelper.interval_date_ids(start_date, end_date))
              end
            end
          end
        end
      end
    end
  end
end
