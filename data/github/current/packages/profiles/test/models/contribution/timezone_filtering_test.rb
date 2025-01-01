# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionTimezoneFilteringTest < GitHub::TestCase
  class TestContributionWithoutFiltering
    extend Contribution::TimezoneFiltering

    def self.needs_filtering_by_occurred_at?
      false
    end

    def self.use_buffered_range(date_range)
      buffered_time_range(date_range)
    end
  end

  class TestContributionWithFiltering
    extend Contribution::TimezoneFiltering

    def self.needs_filtering_by_occurred_at?
      true
    end

    def self.use_buffered_range(date_range)
      buffered_time_range(date_range)
    end
  end

  context "buffered_time_range" do
    test "raises if the class doesn't need filtering by occurred_at" do
      assert_raises Contribution::TimezoneFiltering::UnnecessaryTimeBuffering do
        TestContributionWithoutFiltering.use_buffered_range(Date.yesterday..Date.today)
      end
    end

    test "doesn't raise if the class needs filtering by occurred_at" do
      assert_nothing_raised do
        TestContributionWithFiltering.use_buffered_range(Date.yesterday..Date.today)
      end
    end
  end
end
