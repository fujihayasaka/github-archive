# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../../../../../test_helpers/date_test_helpers"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AlertTrends::ByAgeTest < GitHub::TestCase
          include ::SecurityOverviewAnalytics::Test::TestHelpers::DateTestHelpers

          QueryParser = ::Search::Queries::SecurityCenter::QueryParser

          fixtures do
            @biz = create(:business)
            @org_admin = create(:user)
            @user_session = create(:user_session, user: @org_admin)
            @org = create(:organization, business: @biz, admin: @org_admin)
            @repo = create(:private_repository, owner: @org)
            @soa_repo = create(:soa_repository, repository: @repo)
            create(:security_overview_analytics_feature_status_revision, repository_metadata: @soa_repo, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

            @fake_today = ::Date.new(2023, 10, 10).freeze
            create_date_entries(from_date: ::Date.new(2022, 1, 1), to_date: ::Date.new(2023, 12, 31))
            create_open_alerts_for_age_groups
            create_closed_alerts_for_age_groups
          end

          setup do
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_class?).returns(true)
            ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
              .any_instance.stubs(:selected_backend_security_features)
              .returns(%w[dependabot_alerts secret_scanning codeql])
          end

          context "date intervals" do
            context "when the start and end dates are less than 1 week apart" do
              test "it returns data for every in between date" do
                res = AlertTrends::ByAge.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  return_alert_count: false,
                  is_open_selected: true,
                ).perform

                dates = res.fetch("< 30 days").map { |r| r.fetch(:x) }

                assert_equal(
                  dates,
                  [
                    ::Date.new(2023, 10, 2),
                    ::Date.new(2023, 10, 3),
                    ::Date.new(2023, 10, 4),
                    ::Date.new(2023, 10, 5)
                  ]
                )
              end
            end

            context "when the start and end dates are more than 8 days apart" do
              test "it returns data for 8 dates" do
                res = AlertTrends::ByAge.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 20),
                  user_session: @user_session,
                  return_alert_count: false,
                  is_open_selected: true,
                ).perform

                dates = res.fetch("< 30 days").map { |r| r.fetch(:x) }

                assert_equal(
                  dates,
                  [
                    ::Date.new(2023, 10, 2),
                    ::Date.new(2023, 10, 4),
                    ::Date.new(2023, 10, 6),
                    ::Date.new(2023, 10, 8),
                    ::Date.new(2023, 10, 11),
                    ::Date.new(2023, 10, 14),
                    ::Date.new(2023, 10, 17),
                    ::Date.new(2023, 10, 20)
                  ]
                )
              end
            end
          end

          context "#perform" do
            context "when is_open_selected is true" do
              test "it returns alert counts grouped by age" do
                res = AlertTrends::ByAge.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: @fake_today - 3.months,
                  end_date: @fake_today,
                  user_session: @user_session,
                  return_alert_count: false,
                  is_open_selected: true,
                ).perform

                expected = {
                  "< 30 days" => [
                    { x: ::Date.new(2023, 7, 10), y: 2 },
                    { x: ::Date.new(2023, 7, 23), y: 1 },
                    { x: ::Date.new(2023, 8, 5), y: 1 },
                    { x: ::Date.new(2023, 8, 18), y: 2 },
                    { x: ::Date.new(2023, 8, 31), y: 2 },
                    { x: ::Date.new(2023, 9, 13), y: 2 },
                    { x: ::Date.new(2023, 9, 26), y: 4 },
                    { x: ::Date.new(2023, 10, 10), y: 2 }
                  ],
                  "31 - 59 days" => [
                    { x: ::Date.new(2023, 7, 10), y: 0 },
                    { x: ::Date.new(2023, 7, 23), y: 1 },
                    { x: ::Date.new(2023, 8, 5), y: 2 },
                    { x: ::Date.new(2023, 8, 18), y: 1 },
                    { x: ::Date.new(2023, 8, 31), y: 1 },
                    { x: ::Date.new(2023, 9, 13), y: 2 },
                    { x: ::Date.new(2023, 9, 26), y: 2 },
                    { x: ::Date.new(2023, 10, 10), y: 2 }
                  ],
                  "60 - 89 days" => [
                    { x: ::Date.new(2023, 7, 10), y: 0 },
                    { x: ::Date.new(2023, 7, 23), y: 0 },
                    { x: ::Date.new(2023, 8, 5), y: 0 },
                    { x: ::Date.new(2023, 8, 18), y: 1 },
                    { x: ::Date.new(2023, 8, 31), y: 2 },
                    { x: ::Date.new(2023, 9, 13), y: 1 },
                    { x: ::Date.new(2023, 9, 26), y: 1 },
                    { x: ::Date.new(2023, 10, 10), y: 2 }
                  ],
                  "90+ days" => [
                    { x: ::Date.new(2023, 7, 10), y: 0 },
                    { x: ::Date.new(2023, 7, 23), y: 0 },
                    { x: ::Date.new(2023, 8, 5), y: 0 },
                    { x: ::Date.new(2023, 8, 18), y: 0 },
                    { x: ::Date.new(2023, 8, 31), y: 0 },
                    { x: ::Date.new(2023, 9, 13), y: 1 },
                    { x: ::Date.new(2023, 9, 26), y: 1 },
                    { x: ::Date.new(2023, 10, 10), y: 2 }
                  ]
                }

                assert_equal(expected, res)
              end

              test "returns zero trend when no security_features are available" do
                ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                  .any_instance.stubs(:selected_backend_security_features)
                  .returns([])

                res = AlertTrends::ByAge.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  return_alert_count: false,
                  is_open_selected: true,
                ).perform

                data_points = (::Date.new(2023, 10, 2)..::Date.new(2023, 10, 5)).map do |date|
                  { x: date, y: 0 }
                end

                expected = {
                  "< 30 days" => data_points.deep_dup,
                  "31 - 59 days" => data_points.deep_dup,
                  "60 - 89 days" => data_points.deep_dup,
                  "90+ days" => data_points.deep_dup
                }

                assert_equal(expected, res)
              end

              context "tool-centric filters" do
                context "dependabot filters" do
                  test "returns open dependabot alert counts for selected ecosystem" do
                    res = AlertTrends::ByAge.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("dependabot.ecosystem:npm"),
                      start_date: @fake_today - 3.months,
                      end_date: @fake_today,
                      user_session: @user_session,
                      return_alert_count: false,
                      is_open_selected: true,
                    ).perform

                    expected = {
                      "< 30 days" => [
                        { x: ::Date.new(2023, 7, 10), y: 1 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 1 },
                        { x: ::Date.new(2023, 8, 31), y: 1 },
                        { x: ::Date.new(2023, 9, 13), y: 0 },
                        { x: ::Date.new(2023, 9, 26), y: 1 },
                        { x: ::Date.new(2023, 10, 10), y: 1 }
                      ],
                      "31 - 59 days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 1 },
                        { x: ::Date.new(2023, 8, 5), y: 1 },
                        { x: ::Date.new(2023, 8, 18), y: 0 },
                        { x: ::Date.new(2023, 8, 31), y: 0 },
                        { x: ::Date.new(2023, 9, 13), y: 1 },
                        { x: ::Date.new(2023, 9, 26), y: 1 },
                        { x: ::Date.new(2023, 10, 10), y: 0 }
                      ],
                      "60 - 89 days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 1 },
                        { x: ::Date.new(2023, 8, 31), y: 1 },
                        { x: ::Date.new(2023, 9, 13), y: 0 },
                        { x: ::Date.new(2023, 9, 26), y: 0 },
                        { x: ::Date.new(2023, 10, 10), y: 1 }
                      ],
                      "90+ days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 0 },
                        { x: ::Date.new(2023, 8, 31), y: 0 },
                        { x: ::Date.new(2023, 9, 13), y: 1 },
                        { x: ::Date.new(2023, 9, 26), y: 1 },
                        { x: ::Date.new(2023, 10, 10), y: 1 }
                      ]
                    }

                    assert_equal(expected, res)
                  end
                end

                context "code scanning filters" do
                  test "returns open codeql alert counts for selected rule ids" do
                    res = AlertTrends::ByAge.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("codeql.rule:some-rule"),
                      start_date: @fake_today - 3.months,
                      end_date: @fake_today,
                      user_session: @user_session,
                      return_alert_count: false,
                      is_open_selected: true,
                    ).perform

                    expected = {
                      "< 30 days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 0 },
                        { x: ::Date.new(2023, 8, 31), y: 0 },
                        { x: ::Date.new(2023, 9, 13), y: 1 },
                        { x: ::Date.new(2023, 9, 26), y: 2 },
                        { x: ::Date.new(2023, 10, 10), y: 1 }
                      ],
                      "31 - 59 days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 0 },
                        { x: ::Date.new(2023, 8, 31), y: 0 },
                        { x: ::Date.new(2023, 9, 13), y: 0 },
                        { x: ::Date.new(2023, 9, 26), y: 0 },
                        { x: ::Date.new(2023, 10, 10), y: 1 }
                      ],
                      "60 - 89 days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 0 },
                        { x: ::Date.new(2023, 8, 31), y: 0 },
                        { x: ::Date.new(2023, 9, 13), y: 0 },
                        { x: ::Date.new(2023, 9, 26), y: 0 },
                        { x: ::Date.new(2023, 10, 10), y: 0 }
                      ],
                      "90+ days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 0 },
                        { x: ::Date.new(2023, 8, 31), y: 0 },
                        { x: ::Date.new(2023, 9, 13), y: 0 },
                        { x: ::Date.new(2023, 9, 26), y: 0 },
                        { x: ::Date.new(2023, 10, 10), y: 0 }
                      ]
                    }

                    assert_equal(expected, res)
                  end
                end

                context "secret scanning filters" do
                  test "returns open alert counts for selected validities" do
                    create_open_secret_scanning_alerts

                    res = AlertTrends::ByAge.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("secret-scanning.validity:active"),
                      start_date: @fake_today - 3.months,
                      end_date: @fake_today,
                      user_session: @user_session,
                      return_alert_count: false,
                      is_open_selected: true,
                    ).perform

                    expected = {
                      "< 30 days" => [
                        { x: ::Date.new(2023, 7, 10), y: 1 },
                        { x: ::Date.new(2023, 7, 23), y: 1 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 0 },
                        { x: ::Date.new(2023, 8, 31), y: 0 },
                        { x: ::Date.new(2023, 9, 13), y: 0 },
                        { x: ::Date.new(2023, 9, 26), y: 1 },
                        { x: ::Date.new(2023, 10, 10), y: 1 }
                      ],
                      "31 - 59 days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 1 },
                        { x: ::Date.new(2023, 8, 18), y: 1 },
                        { x: ::Date.new(2023, 8, 31), y: 0 },
                        { x: ::Date.new(2023, 9, 13), y: 0 },
                        { x: ::Date.new(2023, 9, 26), y: 0 },
                        { x: ::Date.new(2023, 10, 10), y: 0 }
                      ],
                      "60 - 89 days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 0 },
                        { x: ::Date.new(2023, 8, 31), y: 1 },
                        { x: ::Date.new(2023, 9, 13), y: 1 },
                        { x: ::Date.new(2023, 9, 26), y: 1 },
                        { x: ::Date.new(2023, 10, 10), y: 0 }
                      ],
                      "90+ days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 0 },
                        { x: ::Date.new(2023, 8, 31), y: 0 },
                        { x: ::Date.new(2023, 9, 13), y: 0 },
                        { x: ::Date.new(2023, 9, 26), y: 0 },
                        { x: ::Date.new(2023, 10, 10), y: 1 }
                      ]
                    }

                    assert_equal(expected, res)
                  end
                end
              end
            end

            context "when is_open_selected is false" do
              test "it returns alert counts grouped by age" do
                res = AlertTrends::ByAge.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: @fake_today - 3.months,
                  end_date: @fake_today,
                  user_session: @user_session,
                  return_alert_count: false,
                  is_open_selected: false,
                ).perform

                expected = {
                  "< 30 days" => [
                    { x: ::Date.new(2023, 7, 10), y: 0 },
                    { x: ::Date.new(2023, 7, 23), y: 0 },
                    { x: ::Date.new(2023, 8, 5), y: 0 },
                    { x: ::Date.new(2023, 8, 18), y: 0 },
                    { x: ::Date.new(2023, 8, 31), y: 0 },
                    { x: ::Date.new(2023, 9, 13), y: 0 },
                    { x: ::Date.new(2023, 9, 26), y: 2 },
                    { x: ::Date.new(2023, 10, 10), y: 2 }
                  ],
                  "31 - 59 days" => [
                    { x: ::Date.new(2023, 7, 10), y: 0 },
                    { x: ::Date.new(2023, 7, 23), y: 0 },
                    { x: ::Date.new(2023, 8, 5), y: 0 },
                    { x: ::Date.new(2023, 8, 18), y: 1 },
                    { x: ::Date.new(2023, 8, 31), y: 2 },
                    { x: ::Date.new(2023, 9, 13), y: 3 },
                    { x: ::Date.new(2023, 9, 26), y: 3 },
                    { x: ::Date.new(2023, 10, 10), y: 3 }
                  ],
                  "60 - 89 days" => [
                    { x: ::Date.new(2023, 7, 10), y: 0 },
                    { x: ::Date.new(2023, 7, 23), y: 0 },
                    { x: ::Date.new(2023, 8, 5), y: 1 },
                    { x: ::Date.new(2023, 8, 18), y: 1 },
                    { x: ::Date.new(2023, 8, 31), y: 1 },
                    { x: ::Date.new(2023, 9, 13), y: 1 },
                    { x: ::Date.new(2023, 9, 26), y: 1 },
                    { x: ::Date.new(2023, 10, 10), y: 1 }
                  ],
                  "90+ days" => [
                    { x: ::Date.new(2023, 7, 10), y: 2 },
                    { x: ::Date.new(2023, 7, 23), y: 2 },
                    { x: ::Date.new(2023, 8, 5), y: 2 },
                    { x: ::Date.new(2023, 8, 18), y: 2 },
                    { x: ::Date.new(2023, 8, 31), y: 2 },
                    { x: ::Date.new(2023, 9, 13), y: 2 },
                    { x: ::Date.new(2023, 9, 26), y: 2 },
                    { x: ::Date.new(2023, 10, 10), y: 2 }
                  ]
                }

                assert_equal(expected, res)
              end

              test "returns zero trend when no security_features are available" do
                ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                  .any_instance.stubs(:selected_backend_security_features)
                  .returns([])

                res = AlertTrends::ByAge.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  return_alert_count: false,
                  is_open_selected: false,
                ).perform

                data_points = (::Date.new(2023, 10, 2)..::Date.new(2023, 10, 5)).map do |date|
                  { x: date, y: 0 }
                end

                expected = {
                  "< 30 days" => data_points.deep_dup,
                  "31 - 59 days" => data_points.deep_dup,
                  "60 - 89 days" => data_points.deep_dup,
                  "90+ days" => data_points.deep_dup
                }

                assert_equal(expected, res)
              end

              context "tool-centric filters" do
                context "dependabot filters" do
                  test "returns closed dependabot alert counts for selected ecosystem" do
                    res = AlertTrends::ByAge.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("dependabot.ecosystem:npm"),
                      start_date: @fake_today - 3.months,
                      end_date: @fake_today,
                      user_session: @user_session,
                      return_alert_count: false,
                      is_open_selected: false,
                    ).perform

                    expected = {
                      "< 30 days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 0 },
                        { x: ::Date.new(2023, 8, 31), y: 0 },
                        { x: ::Date.new(2023, 9, 13), y: 0 },
                        { x: ::Date.new(2023, 9, 26), y: 1 },
                        { x: ::Date.new(2023, 10, 10), y: 1 }
                      ],
                      "31 - 59 days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 1 },
                        { x: ::Date.new(2023, 8, 31), y: 1 },
                        { x: ::Date.new(2023, 9, 13), y: 1 },
                        { x: ::Date.new(2023, 9, 26), y: 1 },
                        { x: ::Date.new(2023, 10, 10), y: 1 }
                      ],
                      "60 - 89 days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 0 },
                        { x: ::Date.new(2023, 8, 31), y: 0 },
                        { x: ::Date.new(2023, 9, 13), y: 0 },
                        { x: ::Date.new(2023, 9, 26), y: 0 },
                        { x: ::Date.new(2023, 10, 10), y: 0 }
                      ],
                      "90+ days" => [
                        { x: ::Date.new(2023, 7, 10), y: 1 },
                        { x: ::Date.new(2023, 7, 23), y: 1 },
                        { x: ::Date.new(2023, 8, 5), y: 1 },
                        { x: ::Date.new(2023, 8, 18), y: 1 },
                        { x: ::Date.new(2023, 8, 31), y: 1 },
                        { x: ::Date.new(2023, 9, 13), y: 1 },
                        { x: ::Date.new(2023, 9, 26), y: 1 },
                        { x: ::Date.new(2023, 10, 10), y: 1 }
                      ]
                    }

                    assert_equal(expected, res)
                  end
                end

                context "code scanning filters" do
                  test "returns closed codeql alert counts for selected rule ids" do
                    res = AlertTrends::ByAge.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("codeql.rule:some-rule"),
                      start_date: @fake_today - 3.months,
                      end_date: @fake_today,
                      user_session: @user_session,
                      return_alert_count: false,
                      is_open_selected: false,
                    ).perform

                    expected = {
                      "< 30 days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 0 },
                        { x: ::Date.new(2023, 8, 31), y: 0 },
                        { x: ::Date.new(2023, 9, 13), y: 0 },
                        { x: ::Date.new(2023, 9, 26), y: 1 },
                        { x: ::Date.new(2023, 10, 10), y: 1 }
                      ],
                      "31 - 59 days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 0 },
                        { x: ::Date.new(2023, 8, 31), y: 0 },
                        { x: ::Date.new(2023, 9, 13), y: 1 },
                        { x: ::Date.new(2023, 9, 26), y: 1 },
                        { x: ::Date.new(2023, 10, 10), y: 1 }
                      ],
                      "60 - 89 days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 0 },
                        { x: ::Date.new(2023, 8, 31), y: 0 },
                        { x: ::Date.new(2023, 9, 13), y: 0 },
                        { x: ::Date.new(2023, 9, 26), y: 0 },
                        { x: ::Date.new(2023, 10, 10), y: 0 }
                      ],
                      "90+ days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 0 },
                        { x: ::Date.new(2023, 8, 31), y: 0 },
                        { x: ::Date.new(2023, 9, 13), y: 0 },
                        { x: ::Date.new(2023, 9, 26), y: 0 },
                        { x: ::Date.new(2023, 10, 10), y: 0 }
                      ]
                    }

                    assert_equal(expected, res)
                  end
                end

                context "secret scanning filters" do
                  test "returns closed alert counts for selected validities" do
                    create_closed_secret_scanning_alerts

                    res = AlertTrends::ByAge.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("secret-scanning.validity:active"),
                      start_date: @fake_today - 3.months,
                      end_date: @fake_today,
                      user_session: @user_session,
                      return_alert_count: false,
                      is_open_selected: false,
                    ).perform

                    expected = {
                      "< 30 days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 0 },
                        { x: ::Date.new(2023, 8, 31), y: 0 },
                        { x: ::Date.new(2023, 9, 13), y: 0 },
                        { x: ::Date.new(2023, 9, 26), y: 1 },
                        { x: ::Date.new(2023, 10, 10), y: 1 }
                      ],
                      "31 - 59 days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 0 },
                        { x: ::Date.new(2023, 8, 31), y: 0 },
                        { x: ::Date.new(2023, 9, 13), y: 0 },
                        { x: ::Date.new(2023, 9, 26), y: 0 },
                        { x: ::Date.new(2023, 10, 10), y: 0 }
                      ],
                      "60 - 89 days" => [
                        { x: ::Date.new(2023, 7, 10), y: 0 },
                        { x: ::Date.new(2023, 7, 23), y: 0 },
                        { x: ::Date.new(2023, 8, 5), y: 0 },
                        { x: ::Date.new(2023, 8, 18), y: 0 },
                        { x: ::Date.new(2023, 8, 31), y: 0 },
                        { x: ::Date.new(2023, 9, 13), y: 0 },
                        { x: ::Date.new(2023, 9, 26), y: 0 },
                        { x: ::Date.new(2023, 10, 10), y: 0 }
                      ],
                      "90+ days" => [
                        { x: ::Date.new(2023, 7, 10), y: 1 },
                        { x: ::Date.new(2023, 7, 23), y: 1 },
                        { x: ::Date.new(2023, 8, 5), y: 1 },
                        { x: ::Date.new(2023, 8, 18), y: 1 },
                        { x: ::Date.new(2023, 8, 31), y: 1 },
                        { x: ::Date.new(2023, 9, 13), y: 1 },
                        { x: ::Date.new(2023, 9, 26), y: 1 },
                        { x: ::Date.new(2023, 10, 10), y: 1 }
                      ]
                    }

                    assert_equal(expected, res)
                  end
                end
              end
            end

            context "when reporting period doesn't include any revisions" do
              test "it returns empty data" do
                res = AlertTrends::ByAge.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: @fake_today - 480.days,
                  end_date: @fake_today - 380.days,
                  user_session: @user_session,
                  return_alert_count: false,
                  is_open_selected: true,
                ).perform

                expected = {
                  "< 30 days" => [
                    { x: ::Date.new(2022, 6, 17), y: 0 },
                    { x: ::Date.new(2022, 7, 1), y: 0 },
                    { x: ::Date.new(2022, 7, 15), y: 0 },
                    { x: ::Date.new(2022, 7, 29), y: 0 },
                    { x: ::Date.new(2022, 8, 12), y: 0 },
                    { x: ::Date.new(2022, 8, 26), y: 0 },
                    { x: ::Date.new(2022, 9, 10), y: 0 },
                    { x: ::Date.new(2022, 9, 25), y: 0 }
                  ],
                  "31 - 59 days" => [
                    { x: ::Date.new(2022, 6, 17), y: 0 },
                    { x: ::Date.new(2022, 7, 1), y: 0 },
                    { x: ::Date.new(2022, 7, 15), y: 0 },
                    { x: ::Date.new(2022, 7, 29), y: 0 },
                    { x: ::Date.new(2022, 8, 12), y: 0 },
                    { x: ::Date.new(2022, 8, 26), y: 0 },
                    { x: ::Date.new(2022, 9, 10), y: 0 },
                    { x: ::Date.new(2022, 9, 25), y: 0 }
                  ],
                  "60 - 89 days" => [
                    { x: ::Date.new(2022, 6, 17), y: 0 },
                    { x: ::Date.new(2022, 7, 1), y: 0 },
                    { x: ::Date.new(2022, 7, 15), y: 0 },
                    { x: ::Date.new(2022, 7, 29), y: 0 },
                    { x: ::Date.new(2022, 8, 12), y: 0 },
                    { x: ::Date.new(2022, 8, 26), y: 0 },
                    { x: ::Date.new(2022, 9, 10), y: 0 },
                    { x: ::Date.new(2022, 9, 25), y: 0 }
                  ],
                  "90+ days" => [
                    { x: ::Date.new(2022, 6, 17), y: 0 },
                    { x: ::Date.new(2022, 7, 1), y: 0 },
                    { x: ::Date.new(2022, 7, 15), y: 0 },
                    { x: ::Date.new(2022, 7, 29), y: 0 },
                    { x: ::Date.new(2022, 8, 12), y: 0 },
                    { x: ::Date.new(2022, 8, 26), y: 0 },
                    { x: ::Date.new(2022, 9, 10), y: 0 },
                    { x: ::Date.new(2022, 9, 25), y: 0 }
                  ]
                }

                assert_equal(expected, res)
              end
            end

            context "when reporting period doesn't include revisions for some sample dates" do
              test "it returns partially empty data" do
                res = AlertTrends::ByAge.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: @fake_today - 480.days,
                  end_date: @fake_today - 2.months,
                  user_session: @user_session,
                  return_alert_count: false,
                  is_open_selected: true,
                ).perform

                expected = {
                  "< 30 days" => [
                     { x: ::Date.new(2022, 6, 17), y: 0 },
                     { x: ::Date.new(2022, 8, 15), y: 0 },
                     { x: ::Date.new(2022, 10, 14), y: 0 },
                     { x: ::Date.new(2022, 12, 13), y: 0 },
                     { x: ::Date.new(2023, 2, 11), y: 0 },
                     { x: ::Date.new(2023, 4, 12), y: 0 },
                     { x: ::Date.new(2023, 6, 11), y: 0 },
                     { x: ::Date.new(2023, 8, 10), y: 2 }
                  ],
                  "31 - 59 days" => [
                     { x: ::Date.new(2022, 6, 17), y: 0 },
                     { x: ::Date.new(2022, 8, 15), y: 0 },
                     { x: ::Date.new(2022, 10, 14), y: 0 },
                     { x: ::Date.new(2022, 12, 13), y: 0 },
                     { x: ::Date.new(2023, 2, 11), y: 0 },
                     { x: ::Date.new(2023, 4, 12), y: 0 },
                     { x: ::Date.new(2023, 6, 11), y: 0 },
                     { x: ::Date.new(2023, 8, 10), y: 1 }
                  ],
                  "60 - 89 days" => [
                     { x: ::Date.new(2022, 6, 17), y: 0 },
                     { x: ::Date.new(2022, 8, 15), y: 0 },
                     { x: ::Date.new(2022, 10, 14), y: 0 },
                     { x: ::Date.new(2022, 12, 13), y: 0 },
                     { x: ::Date.new(2023, 2, 11), y: 0 },
                     { x: ::Date.new(2023, 4, 12), y: 0 },
                     { x: ::Date.new(2023, 6, 11), y: 0 },
                     { x: ::Date.new(2023, 8, 10), y: 1 }
                  ],
                  "90+ days" => [
                     { x: ::Date.new(2022, 6, 17), y: 0 },
                     { x: ::Date.new(2022, 8, 15), y: 0 },
                     { x: ::Date.new(2022, 10, 14), y: 0 },
                     { x: ::Date.new(2022, 12, 13), y: 0 },
                     { x: ::Date.new(2023, 2, 11), y: 0 },
                     { x: ::Date.new(2023, 4, 12), y: 0 },
                     { x: ::Date.new(2023, 6, 11), y: 0 },
                     { x: ::Date.new(2023, 8, 10), y: 0 }
                  ]
                }

                assert_equal(expected, res)
              end
            end
          end

          sig { void }
          def create_open_alerts_for_age_groups
            # Less than 30 days old
            create(:soa_code_scanning_alert_revision, alert_number: 1, repository: @repo, alert_created_at: @fake_today - 15.days, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 15.days), rule_sarif_identifier: "some-rule")
            create(:soa_dependabot_alert_revision, alert_number: 2, repository: @repo, alert_created_at: @fake_today - 20.days, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 20.days), ecosystem: "npm")

            # 30 to 59 days old
            create(:soa_code_scanning_alert_revision, alert_number: 3, repository: @repo, alert_created_at: @fake_today - 35.days, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 35.days), rule_sarif_identifier: "some-rule")
            create(:soa_secret_scanning_alert_revision, alert_number: 4, repository: @repo, alert_created_at: @fake_today - 40.days, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 40.days))

            # 60 to 89 days old
            create(:soa_dependabot_alert_revision, alert_number: 5, repository: @repo, alert_created_at: @fake_today - 65.days, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 65.days), ecosystem: "npm")
            create(:soa_secret_scanning_alert_revision, alert_number: 6, repository: @repo, alert_created_at: @fake_today - 70.days, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 70.days))

            # 90 days old
            create(:soa_code_scanning_alert_revision, alert_number: 7, repository: @repo, alert_created_at: @fake_today - 100.days, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 100.days), rule_sarif_identifier: "other-rule")
            create(:soa_dependabot_alert_revision, alert_number: 8, repository: @repo, alert_created_at: @fake_today - 120.days, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 120.days), ecosystem: "npm")
          end

          sig { void }
          def create_closed_alerts_for_age_groups
            # Less than 30 days old
            create(:soa_code_scanning_alert_revision, alert_number: 9, repository: @repo, alert_created_at: @fake_today - 30.days, alert_resolved_at: @fake_today - 15.days, alert_resolved: true, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 15.days), rule_sarif_identifier: "some-rule")
            create(:soa_dependabot_alert_revision, alert_number: 10, repository: @repo, alert_created_at: @fake_today - 40.days, alert_resolved_at: @fake_today - 20.days, alert_resolved: true, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 20.days), ecosystem: "npm")

            # 30 to 59 days old
            create(:soa_code_scanning_alert_revision, alert_number: 11, repository: @repo, alert_created_at: @fake_today - 70.days, alert_resolved_at: @fake_today - 35.days, alert_resolved: true, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 35.days), rule_sarif_identifier: "some-rule")
            create(:soa_secret_scanning_alert_revision, alert_number: 12, repository: @repo, alert_created_at: @fake_today - 80.days, alert_resolved_at: @fake_today - 40.days, alert_resolved: true, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 40.days))

            # 60 to 89 days old
            create(:soa_dependabot_alert_revision, alert_number: 13, repository: @repo, alert_created_at: @fake_today - 120.days, alert_resolved_at: @fake_today - 65.days, alert_resolved: true, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 65.days), ecosystem: "npm")
            create(:soa_secret_scanning_alert_revision, alert_number: 14, repository: @repo, alert_created_at: @fake_today - 140.days, alert_resolved_at: @fake_today - 70.days, alert_resolved: true, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 70.days))

            # 90 days old
            create(:soa_code_scanning_alert_revision, alert_number: 15, repository: @repo, alert_created_at: @fake_today - 200.days, alert_resolved_at: @fake_today - 100.days, alert_resolved: true, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 100.days), rule_sarif_identifier: "other-rule")
            create(:soa_dependabot_alert_revision, alert_number: 16, repository: @repo, alert_created_at: @fake_today - 240.days, alert_resolved_at: @fake_today - 120.days, alert_resolved: true, date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 120.days), ecosystem: "npm")
          end

          sig { void }
          def create_open_secret_scanning_alerts
            # Less than 30 days old
            create(:soa_secret_scanning_alert_revision,
              alert_number: 17,
              repository: @repo,
              alert_created_at: @fake_today - 15.days,
              date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 15.days),
              alert_type_slug: "amazon_secret_key",
              alert_type_provider: "Amazon AWS",
              alert_bypassed: false,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE
            )
            create(:soa_secret_scanning_alert_revision,
              alert_number: 18,
              repository: @repo,
              alert_created_at: @fake_today - 20.days,
              date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 20.days),
              alert_type_slug: "github_token",
              alert_type_provider: "GitHub",
              alert_bypassed: true,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_INACTIVE
            )

            # 30 to 59 days old
            create(:soa_secret_scanning_alert_revision,
              alert_number: 19,
              repository: @repo,
              alert_created_at: @fake_today - 35.days,
              date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 35.days),
              alert_type_slug: "cp_1",
              alert_type_provider: "",
              alert_bypassed: false,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_UNKNOWN
            )
            create(:soa_secret_scanning_alert_revision,
              alert_number: 20,
              repository: @repo,
              alert_created_at: @fake_today - 40.days,
              date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 40.days),
              alert_type_slug: "amazon_access_key",
              alert_type_provider: "Amazon AWS",
              alert_bypassed: true,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_REVOKED
            )
            # 60 to 89 days old
            create(:soa_secret_scanning_alert_revision,
              alert_number: 21,
              repository: @repo,
              alert_created_at: @fake_today - 65.days,
              date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 65.days),
              alert_type_slug: "github_token",
              alert_type_provider: "GitHub",
              alert_bypassed: true,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_UNKNOWN,
            )
            create(:soa_secret_scanning_alert_revision,
              alert_number: 22,
              repository: @repo,
              alert_created_at: @fake_today - 70.days,
              date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 70.days),
              alert_type_slug: "amazon_access_key",
              alert_type_provider: "Amazon AWS",
              alert_bypassed: true,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_INACTIVE
            )

            # 90+ days old
            create(:soa_secret_scanning_alert_revision,
              alert_number: 23,
              repository: @repo,
              alert_created_at: @fake_today - 100.days,
              date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 100.days),
              alert_type_slug: "amazon_secret_key",
              alert_type_provider: "Amazon AWS",
              alert_bypassed: false,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE
            )
            create(:soa_secret_scanning_alert_revision,
              alert_number: 24,
              repository: @repo,
              alert_created_at: @fake_today - 120.days,
              date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 120.days),
              alert_type_slug: "github_token",
              alert_type_provider: "GitHub",
              alert_bypassed: true,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_UNVERIFIABLE,
            )
          end

          sig { void }
          def create_closed_secret_scanning_alerts
            # Less than 30 days old
            create(:soa_secret_scanning_alert_revision,
              alert_number: 25,
              repository: @repo,
              alert_created_at: @fake_today - 30.days,
              alert_resolved_at: @fake_today - 15.days,
              date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 15.days),
              alert_type_slug: "amazon_secret_key",
              alert_type_provider: "Amazon AWS",
              alert_bypassed: false,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE,
              alert_resolved: true
            )
            create(:soa_secret_scanning_alert_revision,
              alert_number: 26,
              repository: @repo,
              alert_created_at: @fake_today - 40.days,
              alert_resolved_at: @fake_today - 20.days,
              date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 20.days),
              alert_type_slug: "github_token",
              alert_type_provider: "GitHub",
              alert_bypassed: true,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_INACTIVE,
              alert_resolved: true
            )

            # 30 to 59 days old
            create(:soa_secret_scanning_alert_revision,
              alert_number: 27,
              repository: @repo,
              alert_created_at: @fake_today - 70.days,
              alert_resolved_at: @fake_today - 35.days,
              date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 35.days),
              alert_type_slug: "cp_1",
              alert_type_provider: "",
              alert_bypassed: false,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_UNKNOWN,
              alert_resolved: true
            )
            create(:soa_secret_scanning_alert_revision,
              alert_number: 28,
              repository: @repo,
              alert_created_at: @fake_today - 80.days,
              alert_resolved_at: @fake_today - 40.days,
              date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 40.days),
              alert_type_slug: "amazon_access_key",
              alert_type_provider: "Amazon AWS",
              alert_bypassed: true,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_REVOKED,
              alert_resolved: true
            )
            # 60 to 89 days old
            create(:soa_secret_scanning_alert_revision,
              alert_number: 29,
              repository: @repo,
              alert_created_at: @fake_today - 120.days,
              alert_resolved_at: @fake_today - 65.days,
              date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 65.days),
              alert_type_slug: "github_token",
              alert_type_provider: "GitHub",
              alert_bypassed: true,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_UNKNOWN,
              alert_resolved: true
            )
            create(:soa_secret_scanning_alert_revision,
              alert_number: 30,
              repository: @repo,
              alert_created_at: @fake_today - 140.days,
              alert_resolved_at: @fake_today - 70.days,
              date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 70.days),
              alert_type_slug: "amazon_access_key",
              alert_type_provider: "Amazon AWS",
              alert_bypassed: true,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_INACTIVE,
              alert_resolved: true
            )

            # 90+ days old
            create(:soa_secret_scanning_alert_revision,
              alert_number: 31,
              repository: @repo,
              alert_created_at: @fake_today - 200.days,
              alert_resolved_at: @fake_today - 100.days,
              date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 100.days),
              alert_type_slug: "amazon_secret_key",
              alert_type_provider: "Amazon AWS",
              alert_bypassed: false,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE,
              alert_resolved: true
            )
            create(:soa_secret_scanning_alert_revision,
              alert_number: 32,
              repository: @repo,
              alert_created_at: @fake_today - 240.days,
              alert_resolved_at: @fake_today - 120.days,
              date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@fake_today - 120.days),
              alert_type_slug: "github_token",
              alert_type_provider: "GitHub",
              alert_bypassed: true,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_UNVERIFIABLE,
              alert_resolved: true
            )
          end
        end
      end
    end
  end
end
