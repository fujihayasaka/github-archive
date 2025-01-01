# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Metrics::AdoptionTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @org = create(:copilot_for_business_enabled_organization)

    @active_seat = create(:copilot_seat, organization: @org)
    @inactive_seat = create(:copilot_seat, organization: @org)
    @seat_with_no_authentication = create(:copilot_seat, organization: @org)
    @seat_with_old_activity = create(:copilot_seat, organization: @org)
    @seat_with_old_authentication = create(:copilot_seat, organization: @org)

    create(:copilot_activity, seat: @active_seat, activity_at: 1.day.ago)
    create(:copilot_authentication, seat: @active_seat, authentication_at: 1.day.ago)
    create(:copilot_authentication, seat: @inactive_seat, authentication_at: 1.day.ago)
    create(:copilot_activity, seat: @seat_with_old_activity, activity_at: 1.month.ago)
    create(:copilot_authentication, seat: @seat_with_old_activity, authentication_at: 1.month.ago)
    create(:copilot_authentication, seat: @seat_with_old_authentication, authentication_at: 1.month.ago)
  end

  context "#current_payload" do
    test "it returns the correct payload when the flag is enabled for the org" do
      enable_feature_flag(:copilot_metrics_access_page_updates, @org)
      usage_metrics = Copilot::Metrics::Adoption.new(owner: @org)
      payload = usage_metrics.current_payload

      assert_equal 5, payload[:total] # all assigned seats
      assert_equal 1, payload[:active] # seats with activity in the last 28 days
      assert_equal 1, payload[:inactive] # seats with authentication in the last 28 days but no activity
      assert_equal 3, payload[:dormant] # seats with no authentication in the last 28 days
    end

    test "it returns the correct payload when the flag is enabled for the org's business" do
      enable_feature_flag(:copilot_metrics_access_page_updates, @org.business)
      usage_metrics = Copilot::Metrics::Adoption.new(owner: @org)
      payload = usage_metrics.current_payload

      assert_equal 5, payload[:total]
      assert_equal 1, payload[:active]
      assert_equal 1, payload[:inactive]
      assert_equal 3, payload[:dormant]
    end

    test "it returns the null payload when the feature flag is disabled" do
      disable_feature_flag(:copilot_metrics_access_page_updates)
      usage_metrics = Copilot::Metrics::Adoption.new(owner: @org)
      payload = usage_metrics.current_payload

      assert_equal 0, payload[:total]
      assert_equal 0, payload[:active]
      assert_equal 0, payload[:inactive]
      assert_equal 0, payload[:dormant]
    end
  end

  context "#historical_payload" do
    test "correctly aggregates historical data" do
      travel_to("2025-01-22") do # This is a Thursday, so the current week is incomplete and should not be included
        latest_monday = Date.new(2025, 1, 13)
        org = create(:copilot_for_business_enabled_organization)

        recent_active = create(:copilot_seat, organization: org, created_at: latest_monday)
        inactive = create(:copilot_seat, organization: org, created_at: latest_monday - 7.days)
        destroyed = create(:copilot_seat, organization: org, created_at: latest_monday - 14.days)
        slow_onboard = create(:copilot_seat, organization: org, created_at: latest_monday - 21.days)
        inside_lookback_window = create(:copilot_seat, organization: org, created_at: latest_monday - 28.days)
        outside_lookback_window = create(:copilot_seat, organization: org, created_at: latest_monday - 35.days)
        old_destroyed = create(:copilot_seat, organization: org, created_at: latest_monday - 1.year)

        # Active for only the most recent week
        create(:copilot_authentication_history, seat: recent_active, authentication_date: latest_monday)
        create(:copilot_activity_history, seat: recent_active, activity_date: latest_monday)

        # Inactive
        create(:copilot_authentication_history, seat: inactive, authentication_date: latest_monday - 7.days)

        # This seat should appear active this week and only contribute to the total this week
        create(:copilot_authentication_history, seat: destroyed, authentication_date: latest_monday - 14.days)
        create(:copilot_activity_history, seat: destroyed, activity_date: latest_monday - 14.days)
        Copilot::SeatHistory.find_by!(seat_id: destroyed.id).update(seat_deleted_at: latest_monday - 10.days)

        # This seat not have auth until the week after it's created. It won't have activity until a week after that.
        create(:copilot_authentication_history, seat: slow_onboard, authentication_date: latest_monday - 14.days)
        create(:copilot_activity_history, seat: slow_onboard, activity_date: latest_monday - 7.days)

        # This seat is active and in the lookback window for 5 total weeks
        create(:copilot_authentication_history, seat: inside_lookback_window, authentication_date: latest_monday - 28.days)
        create(:copilot_activity_history, seat: inside_lookback_window, activity_date: latest_monday - 28.days)

        # This seat is active but outside the lookback window for the most recent week, so we should not see it active then
        create(:copilot_authentication_history, seat: outside_lookback_window, authentication_date: latest_monday - 35.days)
        create(:copilot_activity_history, seat: outside_lookback_window, activity_date: latest_monday - 35.days)

        # This seat had activity but was deleted more than 100 days ago, so it should not be included at all
        create(:copilot_authentication_history, seat: old_destroyed, authentication_date: latest_monday - 1.year)
        create(:copilot_activity_history, seat: old_destroyed, activity_date: latest_monday - 1.year)
        Copilot::SeatHistory.find_by!(seat_id: old_destroyed.id).update(seat_deleted_at: latest_monday - 1.year)

        payload = Copilot::Metrics::Adoption.new(owner: org).historical_payload

        # We can look back as far as 14 weeks, but we only have data for the last 6 weeks so we should trim the rest
        assert_equal Date.new(2024, 12, 9), payload[:overallStartDate]
        assert_equal Date.new(2025, 1, 19), payload[:overallEndDate]
        assert_equal 6, payload[:historicalAdoptionData].length

        data = payload[:historicalAdoptionData]
        assert_equal data[0], {
          id: "2024-12-09",
          label: "Week 50",
          shortLabel: "W50",
          startDate: Date.new(2024, 12, 9),
          endDate: Date.new(2024, 12, 15),
          total: 1, # outside_lookback_window
          active: 1, # outside_lookback_window
          inactive: 0,
          notOnboarded: 0
        }

        assert_equal data[1], {
          id: "2024-12-16",
          label: "Week 51",
          shortLabel: "W51",
          startDate: Date.new(2024, 12, 16),
          endDate: Date.new(2024, 12, 22),
          total: 2, # outside_lookback_window, inside_lookback_window
          active: 2, # outside_lookback_window, inside_lookback_window
          inactive: 0,
          notOnboarded: 0
        }

        assert_equal data[2], {
          id: "2024-12-23",
          label: "Week 52",
          shortLabel: "W52",
          startDate: Date.new(2024, 12, 23),
          endDate: Date.new(2024, 12, 29),
          total: 3, # outside_lookback_window, inside_lookback_window, slow_onboard
          active: 2, # outside_lookback_window, inside_lookback_window
          inactive: 0,
          notOnboarded: 1 # slow_onboard
        }

        # The destroyed seat should be present this week and never again
        # slow_onboard gained auth this week, but not activity. It is now inactive
        assert_equal data[3], {
          id: "2024-12-30",
          label: "Week 1", # Correctly handles the week spanning two years
          shortLabel: "W1",
          startDate: Date.new(2024, 12, 30),
          endDate: Date.new(2025, 1, 5),
          total: 4, # outside_lookback_window, inside_lookback_window, slow_onboard, destroyed
          active: 3, # outside_lookback_window, inside_lookback_window, destroyed
          inactive: 1, # slow_onboard
          notOnboarded: 0
        }

        # slow_onboard gained activity this week. It is now active
        assert_equal data[4], {
          id: "2025-01-06",
          label: "Week 2", # Correctly handles the week spanning two years
          shortLabel: "W2",
          startDate: Date.new(2025, 1, 6),
          endDate: Date.new(2025, 1, 12),
          total: 4, # outside_lookback_window, inside_lookback_window, slow_onboard, inactive
          active: 3, # outside_lookback_window, inside_lookback_window, slow_onboard
          inactive: 1, # inactive
          notOnboarded: 0
        }

        # outside_lookback_window should no longer appear in active. It is now dormant
        assert_equal data[5], {
          id: "2025-01-13",
          label: "Week 3", # Correctly handles the week spanning two years
          shortLabel: "W3",
          startDate: Date.new(2025, 1, 13),
          endDate: Date.new(2025, 1, 19),
          total: 5, # outside_lookback_window, inside_lookback_window, slow_onboard, inactive, recent_active
          active: 3, # inside_lookback_window, older_active, recent_active
          inactive: 1, # inactive
          notOnboarded: 0
        }
      end
    end
  end

  context "#historical_csv" do
    test "correctly converts historical data into csv format" do
      travel_to("2025-01-22") do # This is a Thursday, so the current week is incomplete and should not be included
        latest_monday = Date.new(2025, 1, 13)
        org = create(:copilot_for_business_enabled_organization)

        active = create(:copilot_seat, organization: org, created_at: latest_monday)
        inactive = create(:copilot_seat, organization: org, created_at: latest_monday - 7.days)

        create(:copilot_authentication_history, seat: active, authentication_date: latest_monday)
        create(:copilot_activity_history, seat: active, activity_date: latest_monday)
        create(:copilot_authentication_history, seat: inactive, authentication_date: latest_monday - 7.days)


        csv = CSV.parse(Copilot::Metrics::Adoption.new(owner: org).historical_csv)

        # rubocop:disable Layout/SpaceInsideArrayPercentLiteral
        assert_equal 3, csv.length # header and two weeks of data
        assert_equal %w[label   startDate     endDate       total notOnboarded inactive active], csv[0]
        assert_equal ["Week 2", "2025-01-06", "2025-01-12", "1",  "0",         "1",     "0"], csv[1]
        assert_equal ["Week 3", "2025-01-13", "2025-01-19", "2",  "0",         "1",     "1"], csv[2]
        # rubocop:enable Layout/SpaceInsideArrayPercentLiteral
      end
    end
  end
end
