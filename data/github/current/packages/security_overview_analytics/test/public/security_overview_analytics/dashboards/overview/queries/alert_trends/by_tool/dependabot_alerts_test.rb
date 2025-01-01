# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../../../../../../test_helpers/alert_trends_test_helpers"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AlertTrends::ByTool::DependabotAlertsTest < GitHub::TestCase
          include ::SecurityOverviewAnalytics::Test::TestHelpers::AlertTrendsTestHelpers

          QueryParser = ::Search::Queries::SecurityCenter::QueryParser

          fixtures do
            create_fixtures
          end

          setup do
            ::SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_class?).returns(true)
            ::SecurityCenter::FeatureFlagHelper.stubs(:show_3rd_party_tools?).returns(true)

            ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
              .any_instance.stubs(:selected_backend_security_features)
              .returns(%w[dependabot_alerts secret_scanning codeql])
          end

          test "it returns a hash of the trend name to data points" do
            res = AlertTrends::ByTool::DependabotAlerts.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: @fake_today,
              user_session: @user_session,
              return_alert_count: false,
              is_open_selected: true,
            ).perform

            assert_equal(
              {
                "Dependabot" => [
                  { x: ::Date.new(2023, 10, 2), y: 1 },
                  { x: ::Date.new(2023, 10, 3), y: 1 },
                  { x: ::Date.new(2023, 10, 4), y: 1 },
                  { x: ::Date.new(2023, 10, 5), y: 1 },
                  { x: ::Date.new(2023, 10, 6), y: 1 },
                  { x: ::Date.new(2023, 10, 7), y: 2 },
                  { x: ::Date.new(2023, 10, 8), y: 2 },
                  { x: ::Date.new(2023, 10, 10), y: 3 }
                ]
              },
              res
            )
          end
        end
      end
    end
  end
end
