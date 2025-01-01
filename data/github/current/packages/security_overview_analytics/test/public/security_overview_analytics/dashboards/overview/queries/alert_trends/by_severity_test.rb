# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../../../../../test_helpers/date_test_helpers"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AlertTrends::BySeverityTest < GitHub::TestCase
          include ::SecurityOverviewAnalytics::Test::TestHelpers::DateTestHelpers

          VALID_SECURITY_FEATURES = %w[dependabot_alerts secret_scanning codeql not-code-ql]
          QueryParser = ::Search::Queries::SecurityCenter::QueryParser

          fixtures do
            @biz = create(:business)
            @org_admin = create(:user)
            @user_session = create(:user_session, user: @org_admin)
            @org = create(:organization, business: @biz, admin: @org_admin)
            @repo = create(:private_repository, owner: @org)
            @datetime_sequence = generate_datetime_sequence

            create_date_entries(from_date: ::Date.new(2023, 10, 1), to_date: ::Date.new(2023, 10, 30))
          end

          setup do
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_for_resolution?).returns(true)
            ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
              .any_instance.stubs(:selected_backend_security_features)
              .returns(VALID_SECURITY_FEATURES)
          end

          context "date intervals" do
            context "when the start and end dates are less than 1 week apart" do
              test "it returns data for every in between date" do
                alert_trends = AlertTrends::BySeverity.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                dates = alert_trends.fetch("Low").map { |r| r.fetch(:x) }

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
                alert_trends = AlertTrends::BySeverity.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 20),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform
                dates = alert_trends.fetch("Low").map { |r| r.fetch(:x) }

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
              test "tracks alerts across the three tables and four severities" do
                repo_model = create(:soa_repository, repository: @repo)
                create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                # Alert opened before the start date and open on the end date
                create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: ::Date.new(2023, 10, 1))

                # Alert opened before the start date and closed during the period
                create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
                create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                # Code scanning with 3rd party tool (included)
                create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1))
                create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                # Alert opened during the period and closed during the period
                create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))
                create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))

                # Alert opened during the period and open on the end date
                create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: ::Date.new(2023, 10, 3))

                # Alert opened on the end date
                create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: ::Date.new(2023, 10, 5))

                alert_trends = AlertTrends::BySeverity.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                expected = {
                  "Low" => [
                    { x: ::Date.new(2023, 10, 2), y: 0 },
                    { x: ::Date.new(2023, 10, 3), y: 1 },
                    { x: ::Date.new(2023, 10, 4), y: 1 },
                    { x: ::Date.new(2023, 10, 5), y: 1 }
                  ],
                  "Medium" => [
                    { x: ::Date.new(2023, 10, 2), y: 1 },
                    { x: ::Date.new(2023, 10, 3), y: 1 },
                    { x: ::Date.new(2023, 10, 4), y: 1 },
                    { x: ::Date.new(2023, 10, 5), y: 1 }
                  ],
                  "High" => [
                    { x: ::Date.new(2023, 10, 2), y: 2 },
                    { x: ::Date.new(2023, 10, 3), y: 0 },
                    { x: ::Date.new(2023, 10, 4), y: 0 },
                    { x: ::Date.new(2023, 10, 5), y: 0 }
                  ],
                  "Critical" => [
                    { x: ::Date.new(2023, 10, 2), y: 1 },
                    { x: ::Date.new(2023, 10, 3), y: 1 },
                    { x: ::Date.new(2023, 10, 4), y: 0 },
                    { x: ::Date.new(2023, 10, 5), y: 1 }
                  ]
                }

                assert_equal(expected, alert_trends)
              end

              test "tracks alerts across the two features and four severities when one of the features is not enabled" do
                repo_model = create(:soa_repository, repository: @repo)
                create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model,
                  date_id: 20231001, dependabot_alerts_enabled: true,
                  code_scanning_enabled: true, secret_scanning_enabled: false,
                  secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                # Alert opened before the start date and open on the end date
                create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: ::Date.new(2023, 10, 1))

                # Alert opened before the start date and closed during the period
                create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
                create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                # Code scanning with 3rd party tool (included)
                create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1))
                create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                # Alert opened during the period and closed during the period
                create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))
                create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))

                # Alert opened during the period and open on the end date
                create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: ::Date.new(2023, 10, 3))

                # Alert opened on the end date
                create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: ::Date.new(2023, 10, 5))

                alert_trends = AlertTrends::BySeverity.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                expected = {
                  "Low" => [
                    { x: ::Date.new(2023, 10, 2), y: 0 },
                    { x: ::Date.new(2023, 10, 3), y: 1 },
                    { x: ::Date.new(2023, 10, 4), y: 1 },
                    { x: ::Date.new(2023, 10, 5), y: 1 }
                  ],
                  "Medium" => [
                    { x: ::Date.new(2023, 10, 2), y: 1 },
                    { x: ::Date.new(2023, 10, 3), y: 1 },
                    { x: ::Date.new(2023, 10, 4), y: 1 },
                    { x: ::Date.new(2023, 10, 5), y: 1 }
                  ],
                  "High" => [
                    { x: ::Date.new(2023, 10, 2), y: 2 },
                    { x: ::Date.new(2023, 10, 3), y: 0 },
                    { x: ::Date.new(2023, 10, 4), y: 0 },
                    { x: ::Date.new(2023, 10, 5), y: 0 }
                  ],
                  "Critical" => [
                    { x: ::Date.new(2023, 10, 2), y: 0 },
                    { x: ::Date.new(2023, 10, 3), y: 0 },
                    { x: ::Date.new(2023, 10, 4), y: 0 },
                    { x: ::Date.new(2023, 10, 5), y: 0 }
                  ]
                }

                assert_equal(expected, alert_trends)
              end

              context "alert-centric filters" do
                test "returns no result when resolution filter is applied" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: ::Date.new(2023, 10, 1))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                  # Code scanning with wrong tool (excluded)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))

                  # Alert opened during the period and open on the end date
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: ::Date.new(2023, 10, 3))

                  # Alert opened on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: ::Date.new(2023, 10, 5))

                  alert_trends = AlertTrends::BySeverity.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("resolution:risk-accepted"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  expected = {
                    "Low" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "Medium" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "High" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "Critical" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ]
                  }

                  assert_equal(expected, alert_trends)
                end

                test "returns alert counts for the specified severities" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: ::Date.new(2023, 10, 1))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                  # Code scanning with wrong tool (excluded)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))

                  # Alert opened during the period and open on the end date
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: ::Date.new(2023, 10, 3))

                  # Alert opened on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: ::Date.new(2023, 10, 5))

                  alert_trends = AlertTrends::BySeverity.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("severity:critical"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  expected = {
                    "Low" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "Medium" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "High" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "Critical" => [
                      { x: ::Date.new(2023, 10, 2), y: 1 },
                      { x: ::Date.new(2023, 10, 3), y: 1 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 1 }
                    ]
                  }

                  assert_equal(expected, alert_trends)
                end
              end

              context "tool-centric filters" do
                context "dependabot filters" do
                  test "returns open dependabot alert counts for selected ecosystem" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    # Non-selected ecosystem should be excluded
                    create(:soa_dependabot_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1), ecosystem: "pip")
                    create(:soa_dependabot_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2, ecosystem: "pip")

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("dependabot.ecosystem:npm"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: true,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 1 },
                        { x: ::Date.new(2023, 10, 3), y: 1 },
                        { x: ::Date.new(2023, 10, 4), y: 1 },
                        { x: ::Date.new(2023, 10, 5), y: 1 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 1 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end
                end

                context "code scanning filters" do
                  test "returns open codeql alert counts for selected rule ids" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    # Non-selected rule should be excluded
                    create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 10, alert_created_at: ::Date.new(2023, 10, 1), rule_sarif_identifier: "other-rule")
                    create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "CodeQL", repository: @repo, alert_number: 10, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2, rule_sarif_identifier: "other-rule")

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("codeql.rule:some-rule"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: true,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 1 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end
                end

                context "secret scanning filters" do
                  test "returns open alert counts for selected token slugs" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("secret-scanning.secret-type:amazon_access_key"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: true,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 1 },
                        { x: ::Date.new(2023, 10, 4), y: 1 },
                        { x: ::Date.new(2023, 10, 5), y: 1 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end

                  test "returns open alert counts for selected token providers" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("secret-scanning.provider:github"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: true,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 1 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 1 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end

                  test "returns open alert counts for selected validities" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("secret-scanning.validity:inactive"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: true,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 2 },
                        { x: ::Date.new(2023, 10, 3), y: 2 },
                        { x: ::Date.new(2023, 10, 4), y: 1 },
                        { x: ::Date.new(2023, 10, 5), y: 1 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end

                  test "returns open alert counts for selected bypass status" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("secret-scanning.bypassed:true"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: true,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 1 },
                        { x: ::Date.new(2023, 10, 3), y: 1 },
                        { x: ::Date.new(2023, 10, 4), y: 1 },
                        { x: ::Date.new(2023, 10, 5), y: 2 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end
                end
              end
            end

            context "when is_open_selected is false" do
              test "tracks alerts across the three tables and four severities" do
                repo_model = create(:soa_repository, repository: @repo)
                create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                # Alert opened before the start date and open on the end date (excluded)
                create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: ::Date.new(2023, 10, 1))

                # Alert opened before the start date and closed during the period
                create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
                create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "CodeQL", repository: @repo, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                # Code scanning with 3rd party tool (included)
                create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1))
                create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                # Alert opened during the period and closed during the period
                create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))
                create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))

                # Alert closed on the end date
                create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 5), alert_created_at: ::Date.new(2023, 10, 5))

                alert_trends = AlertTrends::BySeverity.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: false,
                ).perform

                expected = {
                  "Low" => [
                    { x: ::Date.new(2023, 10, 2), y: 0 },
                    { x: ::Date.new(2023, 10, 3), y: 0 },
                    { x: ::Date.new(2023, 10, 4), y: 0 },
                    { x: ::Date.new(2023, 10, 5), y: 0 }
                  ],
                  "Medium" => [
                    { x: ::Date.new(2023, 10, 2), y: 0 },
                    { x: ::Date.new(2023, 10, 3), y: 0 },
                    { x: ::Date.new(2023, 10, 4), y: 0 },
                    { x: ::Date.new(2023, 10, 5), y: 0 }
                  ],
                  "High" => [
                    { x: ::Date.new(2023, 10, 2), y: 0 },
                    { x: ::Date.new(2023, 10, 3), y: 2 },
                    { x: ::Date.new(2023, 10, 4), y: 2 },
                    { x: ::Date.new(2023, 10, 5), y: 2 }
                  ],
                  "Critical" => [
                    { x: ::Date.new(2023, 10, 2), y: 0 },
                    { x: ::Date.new(2023, 10, 3), y: 0 },
                    { x: ::Date.new(2023, 10, 4), y: 1 },
                    { x: ::Date.new(2023, 10, 5), y: 2 }
                  ]
                }

                assert_equal(expected, alert_trends)
              end

              context "alert-centric filters" do
                test "returns closed alert counts for the selected resolutions" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date (excluded)
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: ::Date.new(2023, 10, 1))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "CodeQL", repository: @repo, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2)

                  # Code scanning with 3rd party tool (included)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2)

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_resolution: 1)

                  # Alert closed on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 5), alert_created_at: ::Date.new(2023, 10, 5,), alert_resolution: 1)

                  alert_trends = AlertTrends::BySeverity.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("resolution:risk-accepted"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: false,
                  ).perform

                  expected = {
                    "Low" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "Medium" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "High" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 2 },
                      { x: ::Date.new(2023, 10, 4), y: 2 },
                      { x: ::Date.new(2023, 10, 5), y: 2 }
                    ],
                    "Critical" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ]
                  }

                  assert_equal(expected, alert_trends)
                end

                test "returns closed alert counts for the selected severities" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date (excluded)
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: ::Date.new(2023, 10, 1))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "CodeQL", repository: @repo, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2)

                  # Code scanning with wrong tool (excluded)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2)

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_resolution: 1)

                  # Alert closed on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 5), alert_created_at: ::Date.new(2023, 10, 5,), alert_resolution: 1)

                  alert_trends = AlertTrends::BySeverity.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("severity:critical"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: false,
                  ).perform

                  expected = {
                    "Low" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "Medium" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "High" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "Critical" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 1 },
                      { x: ::Date.new(2023, 10, 5), y: 2 }
                    ]
                  }

                  assert_equal(expected, alert_trends)
                end
              end

              context "tool-centric filters" do
                context "dependabot filters" do
                  test "returns closed dependabot alert counts for selected ecosystem" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    # Non-selected ecosystem should be excluded
                    create(:soa_dependabot_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1), ecosystem: "pip")
                    create(:soa_dependabot_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2, ecosystem: "pip")

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("dependabot.ecosystem:npm"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: false,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 1 },
                        { x: ::Date.new(2023, 10, 4), y: 1 },
                        { x: ::Date.new(2023, 10, 5), y: 1 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end
                end

                context "code scanning filters" do
                  test "returns closed codeql alert counts for selected rule ids" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    # Non-selected rule should be excluded
                    create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 10, alert_created_at: ::Date.new(2023, 10, 1), rule_sarif_identifier: "other-rule")
                    create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "CodeQL", repository: @repo, alert_number: 10, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2, rule_sarif_identifier: "other-rule")

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("codeql.rule:some-rule"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: false,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 1 },
                        { x: ::Date.new(2023, 10, 4), y: 1 },
                        { x: ::Date.new(2023, 10, 5), y: 1 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end
                end

                context "secret scanning filters" do
                  test "returns closed alert counts for selected token slugs" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("secret-scanning.secret-type:amazon_secret_key"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: false,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 1 },
                        { x: ::Date.new(2023, 10, 5), y: 1 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end

                  test "returns closed alert counts for selected token providers" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("secret-scanning.provider:github"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: false,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 1 },
                        { x: ::Date.new(2023, 10, 4), y: 1 },
                        { x: ::Date.new(2023, 10, 5), y: 1 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end

                  test "returns closed alert counts for selected validities" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("secret-scanning.validity:inactive"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: false,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 1 },
                        { x: ::Date.new(2023, 10, 4), y: 2 },
                        { x: ::Date.new(2023, 10, 5), y: 2 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end

                  test "returns closed alert counts for selected bypassed status" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("secret-scanning.bypassed:true"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: false,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 1 },
                        { x: ::Date.new(2023, 10, 4), y: 1 },
                        { x: ::Date.new(2023, 10, 5), y: 1 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end
                end
              end
            end

            test "returns zero trend when no security_features are available" do
              ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                  .any_instance.stubs(:selected_backend_security_features)
                  .returns([])

              alert_trends = AlertTrends::BySeverity.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new("secret-scanning.bypassed:true"),
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              data_points = (::Date.new(2023, 10, 2)..::Date.new(2023, 10, 5)).map do |date|
                { x: date, y: 0 }
              end

              expected = {
                "Low" => data_points.deep_dup,
                "Medium" => data_points.deep_dup,
                "High" => data_points.deep_dup,
                "Critical" => data_points.deep_dup
              }

              assert_equal(expected, alert_trends)
            end
          end

          context "#perform with alert_revisions_load_async" do
            context "when is_open_selected is true" do
              test "tracks alerts across the three tables and four severities" do
                repo_model = create(:soa_repository, repository: @repo)
                create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                # Alert opened before the start date and open on the end date
                create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: ::Date.new(2023, 10, 1))

                # Alert opened before the start date and closed during the period
                create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
                create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                # Code scanning with 3rd party tool (included)
                create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1))
                create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                # Alert opened during the period and closed during the period
                create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))
                create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))

                # Alert opened during the period and open on the end date
                create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: ::Date.new(2023, 10, 3))

                # Alert opened on the end date
                create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: ::Date.new(2023, 10, 5))

                alert_trends = AlertTrends::BySeverity.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                expected = {
                  "Low" => [
                    { x: ::Date.new(2023, 10, 2), y: 0 },
                    { x: ::Date.new(2023, 10, 3), y: 1 },
                    { x: ::Date.new(2023, 10, 4), y: 1 },
                    { x: ::Date.new(2023, 10, 5), y: 1 }
                  ],
                  "Medium" => [
                    { x: ::Date.new(2023, 10, 2), y: 1 },
                    { x: ::Date.new(2023, 10, 3), y: 1 },
                    { x: ::Date.new(2023, 10, 4), y: 1 },
                    { x: ::Date.new(2023, 10, 5), y: 1 }
                  ],
                  "High" => [
                    { x: ::Date.new(2023, 10, 2), y: 2 },
                    { x: ::Date.new(2023, 10, 3), y: 0 },
                    { x: ::Date.new(2023, 10, 4), y: 0 },
                    { x: ::Date.new(2023, 10, 5), y: 0 }
                  ],
                  "Critical" => [
                    { x: ::Date.new(2023, 10, 2), y: 1 },
                    { x: ::Date.new(2023, 10, 3), y: 1 },
                    { x: ::Date.new(2023, 10, 4), y: 0 },
                    { x: ::Date.new(2023, 10, 5), y: 1 }
                  ]
                }

                assert_equal(expected, alert_trends)
              end

              test "tracks alerts across the two features and four severities when one of the features is not enabled" do
                repo_model = create(:soa_repository, repository: @repo)
                create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model,
                  date_id: 20231001, dependabot_alerts_enabled: true,
                  code_scanning_enabled: true, secret_scanning_enabled: false,
                  secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                # Alert opened before the start date and open on the end date
                create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: ::Date.new(2023, 10, 1))

                # Alert opened before the start date and closed during the period
                create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
                create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                # Code scanning with 3rd party tool (included)
                create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1))
                create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                # Alert opened during the period and closed during the period
                create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))
                create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))

                # Alert opened during the period and open on the end date
                create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: ::Date.new(2023, 10, 3))

                # Alert opened on the end date
                create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: ::Date.new(2023, 10, 5))

                alert_trends = AlertTrends::BySeverity.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                expected = {
                  "Low" => [
                    { x: ::Date.new(2023, 10, 2), y: 0 },
                    { x: ::Date.new(2023, 10, 3), y: 1 },
                    { x: ::Date.new(2023, 10, 4), y: 1 },
                    { x: ::Date.new(2023, 10, 5), y: 1 }
                  ],
                  "Medium" => [
                    { x: ::Date.new(2023, 10, 2), y: 1 },
                    { x: ::Date.new(2023, 10, 3), y: 1 },
                    { x: ::Date.new(2023, 10, 4), y: 1 },
                    { x: ::Date.new(2023, 10, 5), y: 1 }
                  ],
                  "High" => [
                    { x: ::Date.new(2023, 10, 2), y: 2 },
                    { x: ::Date.new(2023, 10, 3), y: 0 },
                    { x: ::Date.new(2023, 10, 4), y: 0 },
                    { x: ::Date.new(2023, 10, 5), y: 0 }
                  ],
                  "Critical" => [
                    { x: ::Date.new(2023, 10, 2), y: 0 },
                    { x: ::Date.new(2023, 10, 3), y: 0 },
                    { x: ::Date.new(2023, 10, 4), y: 0 },
                    { x: ::Date.new(2023, 10, 5), y: 0 }
                  ]
                }

                assert_equal(expected, alert_trends)
              end

              context "alert-centric filters" do
                test "returns no result when resolution filter is applied" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: ::Date.new(2023, 10, 1))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                  # Code scanning with wrong tool (excluded)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))

                  # Alert opened during the period and open on the end date
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: ::Date.new(2023, 10, 3))

                  # Alert opened on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: ::Date.new(2023, 10, 5))

                  alert_trends = AlertTrends::BySeverity.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("resolution:risk-accepted"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  expected = {
                    "Low" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "Medium" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "High" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "Critical" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ]
                  }

                  assert_equal(expected, alert_trends)
                end

                test "returns alert counts for the specified severities" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: ::Date.new(2023, 10, 1))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                  # Code scanning with wrong tool (excluded)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))

                  # Alert opened during the period and open on the end date
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: ::Date.new(2023, 10, 3))

                  # Alert opened on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: ::Date.new(2023, 10, 5))

                  alert_trends = AlertTrends::BySeverity.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("severity:critical"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  expected = {
                    "Low" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "Medium" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "High" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "Critical" => [
                      { x: ::Date.new(2023, 10, 2), y: 1 },
                      { x: ::Date.new(2023, 10, 3), y: 1 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 1 }
                    ]
                  }

                  assert_equal(expected, alert_trends)
                end
              end

              context "tool-centric filters" do
                context "dependabot filters" do
                  test "returns open dependabot alert counts for selected ecosystem" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    # Non-selected ecosystem should be excluded
                    create(:soa_dependabot_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1), ecosystem: "pip")
                    create(:soa_dependabot_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2, ecosystem: "pip")

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("dependabot.ecosystem:npm"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: true,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 1 },
                        { x: ::Date.new(2023, 10, 3), y: 1 },
                        { x: ::Date.new(2023, 10, 4), y: 1 },
                        { x: ::Date.new(2023, 10, 5), y: 1 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 1 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end
                end

                context "code scanning filters" do
                  test "returns open codeql alert counts for selected rule ids" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    # Non-selected rule should be excluded
                    create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 10, alert_created_at: ::Date.new(2023, 10, 1), rule_sarif_identifier: "other-rule")
                    create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "CodeQL", repository: @repo, alert_number: 10, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2, rule_sarif_identifier: "other-rule")

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("codeql.rule:some-rule"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: true,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 1 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end
                end

                context "secret scanning filters" do
                  test "returns open alert counts for selected token slugs" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("secret-scanning.secret-type:amazon_access_key"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: true,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 1 },
                        { x: ::Date.new(2023, 10, 4), y: 1 },
                        { x: ::Date.new(2023, 10, 5), y: 1 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end

                  test "returns open alert counts for selected token providers" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("secret-scanning.provider:github"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: true,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 1 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 1 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end

                  test "returns open alert counts for selected validities" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("secret-scanning.validity:inactive"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: true,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 2 },
                        { x: ::Date.new(2023, 10, 3), y: 2 },
                        { x: ::Date.new(2023, 10, 4), y: 1 },
                        { x: ::Date.new(2023, 10, 5), y: 1 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end

                  test "returns open alert counts for selected bypass status" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("secret-scanning.bypassed:true"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: true,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 1 },
                        { x: ::Date.new(2023, 10, 3), y: 1 },
                        { x: ::Date.new(2023, 10, 4), y: 1 },
                        { x: ::Date.new(2023, 10, 5), y: 2 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end
                end
              end
            end

            context "when is_open_selected is false" do
              test "tracks alerts across the three tables and four severities" do
                repo_model = create(:soa_repository, repository: @repo)
                create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                # Alert opened before the start date and open on the end date (excluded)
                create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: ::Date.new(2023, 10, 1))

                # Alert opened before the start date and closed during the period
                create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
                create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "CodeQL", repository: @repo, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                # Code scanning with 3rd party tool (included)
                create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1))
                create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

                # Alert opened during the period and closed during the period
                create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))
                create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))

                # Alert closed on the end date
                create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 5), alert_created_at: ::Date.new(2023, 10, 5))

                alert_trends = AlertTrends::BySeverity.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: false,
                ).perform

                expected = {
                  "Low" => [
                    { x: ::Date.new(2023, 10, 2), y: 0 },
                    { x: ::Date.new(2023, 10, 3), y: 0 },
                    { x: ::Date.new(2023, 10, 4), y: 0 },
                    { x: ::Date.new(2023, 10, 5), y: 0 }
                  ],
                  "Medium" => [
                    { x: ::Date.new(2023, 10, 2), y: 0 },
                    { x: ::Date.new(2023, 10, 3), y: 0 },
                    { x: ::Date.new(2023, 10, 4), y: 0 },
                    { x: ::Date.new(2023, 10, 5), y: 0 }
                  ],
                  "High" => [
                    { x: ::Date.new(2023, 10, 2), y: 0 },
                    { x: ::Date.new(2023, 10, 3), y: 2 },
                    { x: ::Date.new(2023, 10, 4), y: 2 },
                    { x: ::Date.new(2023, 10, 5), y: 2 }
                  ],
                  "Critical" => [
                    { x: ::Date.new(2023, 10, 2), y: 0 },
                    { x: ::Date.new(2023, 10, 3), y: 0 },
                    { x: ::Date.new(2023, 10, 4), y: 1 },
                    { x: ::Date.new(2023, 10, 5), y: 2 }
                  ]
                }

                assert_equal(expected, alert_trends)
              end

              context "alert-centric filters" do
                test "returns closed alert counts for the selected resolutions" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date (excluded)
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: ::Date.new(2023, 10, 1))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "CodeQL", repository: @repo, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2)

                  # Code scanning with 3rd party tool (included)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2)

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_resolution: 1)

                  # Alert closed on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 5), alert_created_at: ::Date.new(2023, 10, 5,), alert_resolution: 1)

                  alert_trends = AlertTrends::BySeverity.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("resolution:risk-accepted"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: false,
                  ).perform

                  expected = {
                    "Low" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "Medium" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "High" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 2 },
                      { x: ::Date.new(2023, 10, 4), y: 2 },
                      { x: ::Date.new(2023, 10, 5), y: 2 }
                    ],
                    "Critical" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ]
                  }

                  assert_equal(expected, alert_trends)
                end

                test "returns closed alert counts for the selected severities" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date (excluded)
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: ::Date.new(2023, 10, 1))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "CodeQL", repository: @repo, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2)

                  # Code scanning with wrong tool (excluded)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2)

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_resolution: 1)

                  # Alert closed on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 5), alert_created_at: ::Date.new(2023, 10, 5,), alert_resolution: 1)

                  alert_trends = AlertTrends::BySeverity.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("severity:critical"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: false,
                  ).perform

                  expected = {
                    "Low" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "Medium" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "High" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 0 },
                      { x: ::Date.new(2023, 10, 5), y: 0 }
                    ],
                    "Critical" => [
                      { x: ::Date.new(2023, 10, 2), y: 0 },
                      { x: ::Date.new(2023, 10, 3), y: 0 },
                      { x: ::Date.new(2023, 10, 4), y: 1 },
                      { x: ::Date.new(2023, 10, 5), y: 2 }
                    ]
                  }

                  assert_equal(expected, alert_trends)
                end
              end

              context "tool-centric filters" do
                context "dependabot filters" do
                  test "returns closed dependabot alert counts for selected ecosystem" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    # Non-selected ecosystem should be excluded
                    create(:soa_dependabot_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1), ecosystem: "pip")
                    create(:soa_dependabot_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2, ecosystem: "pip")

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("dependabot.ecosystem:npm"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: false,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 1 },
                        { x: ::Date.new(2023, 10, 4), y: 1 },
                        { x: ::Date.new(2023, 10, 5), y: 1 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end
                end

                context "code scanning filters" do
                  test "returns closed codeql alert counts for selected rule ids" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    # Non-selected rule should be excluded
                    create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 10, alert_created_at: ::Date.new(2023, 10, 1), rule_sarif_identifier: "other-rule")
                    create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "CodeQL", repository: @repo, alert_number: 10, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2, rule_sarif_identifier: "other-rule")

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("codeql.rule:some-rule"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: false,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 1 },
                        { x: ::Date.new(2023, 10, 4), y: 1 },
                        { x: ::Date.new(2023, 10, 5), y: 1 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end
                end

                context "secret scanning filters" do
                  test "returns closed alert counts for selected token slugs" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("secret-scanning.secret-type:amazon_secret_key"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: false,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 1 },
                        { x: ::Date.new(2023, 10, 5), y: 1 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end

                  test "returns closed alert counts for selected token providers" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("secret-scanning.provider:github"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: false,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 1 },
                        { x: ::Date.new(2023, 10, 4), y: 1 },
                        { x: ::Date.new(2023, 10, 5), y: 1 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end

                  test "returns closed alert counts for selected validities" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("secret-scanning.validity:inactive"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: false,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 1 },
                        { x: ::Date.new(2023, 10, 4), y: 2 },
                        { x: ::Date.new(2023, 10, 5), y: 2 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end

                  test "returns closed alert counts for selected bypassed status" do
                    repo_model = create(:soa_repository, repository: @repo)
                    create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                    create_alert_revisions

                    alert_trends = AlertTrends::BySeverity.for_organization(
                      organization: @org,
                      user: @org_admin,
                      query: QueryParser.new("secret-scanning.bypassed:true"),
                      start_date: ::Date.new(2023, 10, 2),
                      end_date: ::Date.new(2023, 10, 5),
                      user_session: @user_session,
                      is_open_selected: false,
                    ).perform

                    expected = {
                      "Low" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Medium" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "High" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 0 },
                        { x: ::Date.new(2023, 10, 4), y: 0 },
                        { x: ::Date.new(2023, 10, 5), y: 0 }
                      ],
                      "Critical" => [
                        { x: ::Date.new(2023, 10, 2), y: 0 },
                        { x: ::Date.new(2023, 10, 3), y: 1 },
                        { x: ::Date.new(2023, 10, 4), y: 1 },
                        { x: ::Date.new(2023, 10, 5), y: 1 }
                      ]
                    }

                    assert_equal(expected, alert_trends)
                  end
                end
              end
            end

            test "returns zero trend when no security_features are available" do
              ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                  .any_instance.stubs(:selected_backend_security_features)
                  .returns([])

              alert_trends = AlertTrends::BySeverity.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new("secret-scanning.bypassed:true"),
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              data_points = (::Date.new(2023, 10, 2)..::Date.new(2023, 10, 5)).map do |date|
                { x: date, y: 0 }
              end

              expected = {
                "Low" => data_points.deep_dup,
                "Medium" => data_points.deep_dup,
                "High" => data_points.deep_dup,
                "Critical" => data_points.deep_dup
              }

              assert_equal(expected, alert_trends)
            end
          end

          def create_alert_revisions
            # Alert opened before the start date and open on the end date
            create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: ::Date.new(2023, 10, 1), ecosystem: "npm", updated_at: @datetime_sequence[0])

            # Alert opened before the start date and closed during the period
            create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1), rule_sarif_identifier: "some-rule", updated_at: @datetime_sequence[1])
            create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "CodeQL", repository: @repo, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2, rule_sarif_identifier: "some-rule", updated_at: @datetime_sequence[2])
            create(:soa_dependabot_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1), ecosystem: "npm", updated_at: @datetime_sequence[3])
            create(:soa_dependabot_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2, ecosystem: "npm", updated_at: @datetime_sequence[4])

            # Code scanning with wrong tool (excluded)
            create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1), updated_at: @datetime_sequence[5])
            create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: 2, updated_at: @datetime_sequence[6])

            create_secret_scanning_alerts_with_token_metadata
          end

          def create_secret_scanning_alerts_with_token_metadata
            # Alert opened before the start date and open on the end date, with change in validity
            create(:security_overview_analytics_secret_scanning_alert_revision,
              date_id: 20231001,
              next_revision_date_id: 20231004,
              alert_number: 1,
              repository: @repo.repository,
              alert_resolved: false,
              alert_type_slug: "amazon_secret_key",
              alert_type_provider: "Amazon AWS",
              alert_bypassed: false,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE,
              alert_created_at: ::Date.new(2023, 10, 1),
              updated_at: @datetime_sequence[7],
            )
            create(:security_overview_analytics_secret_scanning_alert_revision,
              date_id: 20231004,
              alert_number: 1,
              repository: @repo.repository,
              alert_resolved: true,
              alert_resolution: 1,
              alert_type_slug: "amazon_secret_key",
              alert_type_provider: "Amazon AWS",
              alert_bypassed: false,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_INACTIVE,
              alert_created_at: ::Date.new(2023, 10, 1),
              updated_at: @datetime_sequence[8],
            )
            # Alert opened before the start date and closed during the period
            create(:security_overview_analytics_secret_scanning_alert_revision,
              date_id: 20231001,
              next_revision_date_id: 20231003,
              alert_number: 2,
              repository: @repo.repository,
              alert_resolved: false,
              alert_type_slug: "github_token",
              alert_type_provider: "GitHub",
              alert_bypassed: true,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_INACTIVE,
              alert_created_at: ::Date.new(2023, 10, 1),
              updated_at: @datetime_sequence[9],
            )
            create(:security_overview_analytics_secret_scanning_alert_revision,
              date_id: 20231003,
              alert_number: 2,
              repository: @repo.repository,
              alert_resolved: true,
              alert_resolution: 2,
              alert_type_slug: "github_token",
              alert_type_provider: "GitHub",
              alert_bypassed: true,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_INACTIVE,
              alert_resolved_at: ::Date.new(2023, 10, 3),
              alert_created_at: ::Date.new(2023, 10, 1),
              updated_at: @datetime_sequence[10],
            )
            # Alert opened during the period and closed during the period
            create(:security_overview_analytics_secret_scanning_alert_revision,
              date_id: 20231002,
              next_revision_date_id: 20231004,
              alert_number: 3,
              repository: @repo.repository,
              alert_resolved: false,
              alert_type_slug: "cp_1",
              alert_type_provider: "",
              alert_bypassed: false,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_UNKNOWN,
              alert_created_at: ::Date.new(2023, 10, 2),
              updated_at: @datetime_sequence[11],
            )
            create(:security_overview_analytics_secret_scanning_alert_revision,
              date_id: 20231004,
              alert_number: 3,
              repository: @repo.repository,
              alert_resolved: true,
              alert_resolution: 3,
              alert_type_slug: "cp_1",
              alert_type_provider: "",
              alert_bypassed: false,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_UNKNOWN,
              alert_resolved_at: ::Date.new(2023, 10, 4),
              alert_created_at: ::Date.new(2023, 10, 2),
              updated_at: @datetime_sequence[12],
            )
            # Alert opened during the period and open on the end date
            create(:security_overview_analytics_secret_scanning_alert_revision,
              date_id: 20231003,
              alert_number: 4,
              repository: @repo.repository,
              alert_resolved: false,
              alert_type_slug: "amazon_access_key",
              alert_type_provider: "Amazon AWS",
              alert_bypassed: true,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_REVOKED,
              alert_created_at: ::Date.new(2023, 10, 3),
              updated_at: @datetime_sequence[13],
            )
            # Alert opened on the end date
            create(:security_overview_analytics_secret_scanning_alert_revision,
              date_id: 20231005,
              alert_number: 5,
              repository: @repo.repository,
              alert_resolved: false,
              alert_type_slug: "github_token",
              alert_type_provider: "GitHub",
              alert_bypassed: true,
              alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_UNKNOWN,
              alert_created_at: ::Date.new(2023, 10, 5),
              updated_at: @datetime_sequence[14],
            )
          end

          sig { returns(T::Array[Time]) }
          def generate_datetime_sequence
            # Set up sequence of datetimes that are spaced 1 second apart to test slicing
            # of the alert revisions by date
            now = Time.now
            (1..100).map do |i|
              (now + i.seconds).freeze
            end.freeze
          end
        end
      end
    end
  end
end
