# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionPriorActivityCollectorFetcherTest < GitHub::TestCase
  fixtures do
    @user = Timecop.freeze(Time.zone.parse("August 1 2018 10:00 AM")) { create(:user) }
  end

  def new_collector(time_range:, user: @user)
    Contribution::Collector.new(user: user, time_range: time_range,
                                contribution_classes: [Contribution::JoinedGitHub])
  end

  context "#date_range" do
    test "nil when given collector has activity" do
      time_range = @user.created_at.beginning_of_month..@user.created_at.end_of_month
      collector = new_collector(time_range: time_range)
      fetcher = Contribution::PriorActivityCollectorFetcher.new(collector: collector)

      assert_nil fetcher.date_range
    end

    test "goes no further back than beginning of the month in trying to find previous activity" do
      user = Timecop.freeze("2017-04-11") { create(:user) }
      activity_time = user.created_at
      empty_time = activity_time - 1.month
      time_range = empty_time.beginning_of_month..empty_time.end_of_month
      collector = new_collector(time_range: time_range, user: user)
      fetcher = Contribution::PriorActivityCollectorFetcher.new(collector: collector)

      month_start = empty_time.beginning_of_month
      assert_equal month_start.to_date..month_start.end_of_month.to_date, fetcher.date_range
    end
  end

  context "#time_range_without_activity" do
    test "nil when given collector has activity" do
      time_range = @user.created_at.beginning_of_month..@user.created_at.end_of_month
      collector = new_collector(time_range: time_range)
      fetcher = Contribution::PriorActivityCollectorFetcher.new(collector: collector)

      assert_nil fetcher.time_range_without_activity
    end
  end

  context "#collector_without_activity" do
    test "nil when given collector has activity" do
      time_range = @user.created_at.beginning_of_month..@user.created_at.end_of_month
      collector = new_collector(time_range: time_range)
      fetcher = Contribution::PriorActivityCollectorFetcher.new(collector: collector)

      assert_nil fetcher.collector_without_activity
    end

    test "returns given collector when it has no activity" do
      future_time = @user.created_at + 1.month
      time_range = future_time.beginning_of_month..future_time.end_of_month
      collector = new_collector(time_range: time_range)
      fetcher = Contribution::PriorActivityCollectorFetcher.new(collector: collector)

      assert_equal collector, fetcher.collector_without_activity
    end
  end

  context "#collector_with_activity" do
    test "nil when given collector has activity" do
      time_range = @user.created_at.beginning_of_month..@user.created_at.end_of_month
      collector = new_collector(time_range: time_range)
      fetcher = Contribution::PriorActivityCollectorFetcher.new(collector: collector)

      assert_nil fetcher.collector_with_activity
    end

    test "nil when there is no activity prior to time span of given collector" do
      empty_time = @user.created_at - 1.month
      time_range = empty_time.beginning_of_month..empty_time.end_of_month
      collector = new_collector(time_range: time_range)
      fetcher = Contribution::PriorActivityCollectorFetcher.new(collector: collector)

      assert_nil fetcher.collector_with_activity
    end
  end
end
