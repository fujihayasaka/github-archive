# typed: strict
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class DateTest < GitHub::TestCase
    context "#factorybot" do
      test "can create data" do
        now = Time.now
        by_bot = create(:security_overview_analytics_date, id: 1, date_value: now)
        by_model = T.must(SecurityOverviewAnalytics::Date.find_by(id: by_bot.id))
        assert_equal by_model, by_bot
      end
    end

    context "#timestamps" do
      test "are stored in utc" do
        now = Time.now
        model = create(:security_overview_analytics_date, id: 1, date_value: now)
        # We are storing date without time
        assert_timestamp now.to_date, model.date_value
      end
    end

    context "#relations" do
      test "can access SecurityOverviewAnalytics::FeatureStatusRevision records" do
        model = create(:security_overview_analytics_date)
        revision1 = create(:security_overview_analytics_feature_status_revision, date_id: model.id, next_revision_date_id: model.id + 1)
        revision2 = create(:security_overview_analytics_feature_status_revision, date_id: model.id, next_revision_date_id: model.id + 1)
        assert_equal [revision1, revision2], model.feature_status_revisions.order(:id).to_a
      end
    end

    context "id_from_date" do
      test "returns the id form of a date" do
        date = ::Date.new(2020, 1, 1)
        assert_equal 20200101, SecurityOverviewAnalytics::Date.id_from_date(date)

        date = ::Date.new(2023, 12, 10)
        assert_equal 20231210, SecurityOverviewAnalytics::Date.id_from_date(date)
      end
    end

    context "id_from_time" do
      test "returns the id form of a time" do
        Time.use_zone("America/Denver") do
          Timecop.freeze(Time.utc(2023, 11, 5, 2, 0, 0)) do
            assert_equal 20231105, Date.id_from_time(Time.now)
            assert_equal 20231105, Date.id_from_time(Time.current)
          end
        end
      end
    end

    private

    sig { params(expected: ::Date, actual: ::Date).void }
    def assert_timestamp(expected, actual)
      assert_equal expected.year, actual.year
      assert_equal expected.month, actual.month
      assert_equal expected.day, actual.day
    end
  end
end
