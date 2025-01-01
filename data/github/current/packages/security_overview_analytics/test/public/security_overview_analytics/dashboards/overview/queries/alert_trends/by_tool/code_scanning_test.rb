# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../../../../../../test_helpers/alert_trends_test_helpers"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AlertTrends::ByTool::CodeScanningTest < GitHub::TestCase
          include ::SecurityOverviewAnalytics::Test::TestHelpers::AlertTrendsTestHelpers

          QueryParser = ::Search::Queries::SecurityCenter::QueryParser

          fixtures do
            create_fixtures
          end

          setup do
            ::SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_class?).returns(true)
            ::SecurityCenter::FeatureFlagHelper.stubs(:show_3rd_party_tools?).returns(true)

            @security_features = [::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser::TOOL_CODEQL] + THIRD_PARTY_TOOLS

            ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
              .any_instance.stubs(:selected_backend_security_features)
              .returns(@security_features)
          end

          test "it returns a hash of trend names to data points" do
            res = AlertTrends::ByTool::CodeScanning.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: @fake_today - 60.days,
              end_date: @fake_today,
              user_session: @user_session,
              return_alert_count: false,
              is_open_selected: true,
            ).perform

            assert_equal(
              {
                "CodeQL" => [
                  { x: ::Date.new(2023, 8, 11), y: 0 },
                  { x: ::Date.new(2023, 8, 19), y: 0 },
                  { x: ::Date.new(2023, 8, 27), y: 0 },
                  { x: ::Date.new(2023, 9, 4), y: 0 },
                  { x: ::Date.new(2023, 9, 13), y: 0 },
                  { x: ::Date.new(2023, 9, 22), y: 0 },
                  { x: ::Date.new(2023, 10, 1), y: 0 },
                  { x: ::Date.new(2023, 10, 10), y: 3 }
                ],
                THIRD_PARTY_TOOL_4 => [
                  { x: ::Date.new(2023, 8, 11), y: 0 },
                  { x: ::Date.new(2023, 8, 19), y: 0 },
                  { x: ::Date.new(2023, 8, 27), y: 0 },
                  { x: ::Date.new(2023, 9, 4), y: 0 },
                  { x: ::Date.new(2023, 9, 13), y: 0 },
                  { x: ::Date.new(2023, 9, 22), y: 0 },
                  { x: ::Date.new(2023, 10, 1), y: 1 },
                  { x: ::Date.new(2023, 10, 10), y: 2 }
                ],
                THIRD_PARTY_TOOL_3 => [
                  { x: ::Date.new(2023, 8, 11), y: 0 },
                  { x: ::Date.new(2023, 8, 19), y: 0 },
                  { x: ::Date.new(2023, 8, 27), y: 0 },
                  { x: ::Date.new(2023, 9, 4), y: 0 },
                  { x: ::Date.new(2023, 9, 13), y: 0 },
                  { x: ::Date.new(2023, 9, 22), y: 1 },
                  { x: ::Date.new(2023, 10, 1), y: 2 },
                  { x: ::Date.new(2023, 10, 10), y: 2 }
                ],
                THIRD_PARTY_TOOL_1 => [
                  { x: ::Date.new(2023, 8, 11), y: 0 },
                  { x: ::Date.new(2023, 8, 19), y: 0 },
                  { x: ::Date.new(2023, 8, 27), y: 1 },
                  { x: ::Date.new(2023, 9, 4), y: 2 },
                  { x: ::Date.new(2023, 9, 13), y: 2 },
                  { x: ::Date.new(2023, 9, 22), y: 2 },
                  { x: ::Date.new(2023, 10, 1), y: 2 },
                  { x: ::Date.new(2023, 10, 10), y: 2 }
                ],
                "Other third-party tools" => [
                  { x: ::Date.new(2023, 8, 11), y: 0 },
                  { x: ::Date.new(2023, 8, 19), y: 0 },
                  { x: ::Date.new(2023, 8, 27), y: 0 },
                  { x: ::Date.new(2023, 9, 4), y: 0 },
                  { x: ::Date.new(2023, 9, 13), y: 1 },
                  { x: ::Date.new(2023, 9, 22), y: 1 },
                  { x: ::Date.new(2023, 10, 1), y: 1 },
                  { x: ::Date.new(2023, 10, 10), y: 1 }
                ]
              },
              res.to_h
            )
          end

          context "when CodeQL is in security_features" do
            test "it includes codeql_counts in the results" do
              res = AlertTrends::ByTool::CodeScanning.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: @fake_today - 60.days,
                end_date: @fake_today,
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              ).perform

              assert(res.key?("CodeQL"))
            end

            context "when CodeQL is the only security feature" do
              test "it omits other_third_party_tool_count from the results" do
                ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                  .any_instance.stubs(:selected_backend_security_features)
                  .returns([::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser::TOOL_CODEQL])

                res = AlertTrends::ByTool::CodeScanning.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: @fake_today - 60.days,
                  end_date: @fake_today,
                  user_session: @user_session,
                  return_alert_count: false,
                  is_open_selected: true,
                ).perform

                refute(res.key?("Other third-party tools"))
              end
            end
          end

          context "when CodeQL is not in security_features" do
            test "it omits codeql_counts from the results" do
              ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                  .any_instance.stubs(:selected_backend_security_features)
                  .returns([THIRD_PARTY_TOOLS])

              res = AlertTrends::ByTool::CodeScanning.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: @fake_today - 60.days,
                end_date: @fake_today,
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              ).perform

              refute(res.key?("CodeQL"))
            end
          end

          context "when security_features is empty" do
            test "it returns an empty response" do
              ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                  .any_instance.stubs(:selected_backend_security_features)
                  .returns([])

              res = AlertTrends::ByTool::CodeScanning.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: @fake_today - 60.days,
                end_date: @fake_today,
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              ).perform

              assert_equal({}, res.to_h)
            end
          end
        end
      end
    end
  end
end
