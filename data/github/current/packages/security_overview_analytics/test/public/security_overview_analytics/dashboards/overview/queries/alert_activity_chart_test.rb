# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AlertActivityChartTest < GitHub::TestCase
          VALID_SECURITY_FEATURES = %w[dependabot_alerts secret_scanning codeql not-code-ql]
          QueryParser = ::Search::Queries::SecurityCenter::QueryParser

          fixtures do
            @biz = create(:business)
            @org_admin = create(:user)
            @user_session = create(:user_session, user: @org_admin)
            @org = create(:organization, business: @biz, admin: @org_admin)
            @repo = create(:private_repository, owner: @org)
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
                alert_trends = AlertActivityChart.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                expected = [
                  { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 0 },
                  { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                  { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 0, opened: 0 },
                  { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 0, opened: 0 }
                ]
                assert_equal expected, alert_trends
              end
            end

            context "when the start and end dates are more than 8 days apart" do
              test "it returns data for 8 dates" do
                alert_trends = AlertActivityChart.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 10),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                expected = [
                  { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 0 },
                  { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                  { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 0, opened: 0 },
                  { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 0, opened: 0 },
                  { date: ::Date.new(2023, 10, 6), end_date: ::Date.new(2023, 10, 6), closed: 0, opened: 0 },
                  { date: ::Date.new(2023, 10, 7), end_date: ::Date.new(2023, 10, 8), closed: 0, opened: 0 },
                  { date: ::Date.new(2023, 10, 9), end_date: ::Date.new(2023, 10, 10), closed: 0, opened: 0 }
                ]

                assert_equal expected, alert_trends
              end
            end
          end

          context "#perform" do
            test "tracks open/closed across the three tables for range less than a week with all features enabled" do
              repo_model = create(:soa_repository, repository: @repo)
              create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              create_alert_revisions

              alert_trends = AlertActivityChart.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              expected = [
                { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 1 },
                { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 2, opened: 1 },
                { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 1 }
              ]

              assert_equal expected, alert_trends
            end

            test "tracks open/closed across the three tables for range less than a week with code scanning disabled" do
              repo_model = create(:soa_repository, repository: @repo)
              create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: false, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              create_alert_revisions

              alert_trends = AlertActivityChart.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              expected = [
                { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 1 },
                { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 1 }
              ]

              assert_equal expected, alert_trends
            end

            test "tracks open/closed across the three tables for range less than a week with secret scanning disabled" do
              repo_model = create(:soa_repository, repository: @repo)
              create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: false, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              create_alert_revisions

              alert_trends = AlertActivityChart.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              expected = [
                { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 0 },
                { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 2, opened: 1 },
                { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 0, opened: 0 },
                { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 0, opened: 0 }
              ]

              assert_equal expected, alert_trends
            end

            test "tracks open/closed across the three tables for range less than a week with dependabot alerts disabled" do
              repo_model = create(:soa_repository, repository: @repo)
              create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              create_alert_revisions

              alert_trends = AlertActivityChart.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              expected = [
                { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 1 },
                { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 2, opened: 1 },
                { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 1 }
              ]

              assert_equal expected, alert_trends
            end

            test "tracks open/closed across the three tables for range less than a week with no security features provided" do
              repo_model = create(:soa_repository, repository: @repo)
              create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              create_alert_revisions

              ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                .any_instance.stubs(:selected_backend_security_features)
                .returns([])

              alert_trends = AlertActivityChart.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              expected = [
                { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 0 },
                { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 0, opened: 0 },
                { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 0, opened: 0 }
              ]

              assert_equal expected, alert_trends
            end

            test "tracks open/closed across the three tables for range greater than a week" do
              repo_model = create(:soa_repository, repository: @repo)
              create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # Alert opened before the start date and open on the end date (excluded)
              create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

              # Alert opened before the start date and closed during the period
              create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
              create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

              # Code scanning with 3rd party tool (included)
              create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231013, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
              create(:soa_code_scanning_alert_revision, date_id: 20231013, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-13 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

              # Alert opened during the period and closed during the period
              create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231014, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"))
              create(:soa_secret_scanning_alert_revision, date_id: 20231014, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-14 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"))

              # Alert opened during the period and open on the end date
              create(:soa_code_scanning_alert_revision, date_id: 20231023, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-23 08:00:00"))

              # Alert opened on the end date
              create(:soa_secret_scanning_alert_revision, date_id: 20231031, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-31 08:00:00"))

              # Alert opened on the end date + 1
              create(:soa_secret_scanning_alert_revision, date_id: 20231101, repository: @repo, alert_number: 6, alert_created_at: DateTime.parse("2023-11-01 08:00:00"))

              # Alert closed on the end date
              create(:soa_secret_scanning_alert_revision, date_id: 20231031, repository: @repo, alert_number: 7, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-31 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

              # Alert closed on the end date + 1
              create(:soa_secret_scanning_alert_revision, date_id: 20231101, repository: @repo, alert_number: 8, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-11-01 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

              alert_trends = AlertActivityChart.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 31),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              expected = [
                { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 1 },
                { date: ::Date.new(2023, 10, 6), end_date: ::Date.new(2023, 10, 9), closed: 0, opened: 0 },
                { date: ::Date.new(2023, 10, 10), end_date: ::Date.new(2023, 10, 13), closed: 1, opened: 0 },
                { date: ::Date.new(2023, 10, 14), end_date: ::Date.new(2023, 10, 17), closed: 1, opened: 0 },
                { date: ::Date.new(2023, 10, 18), end_date: ::Date.new(2023, 10, 21), closed: 0, opened: 0 },
                { date: ::Date.new(2023, 10, 22), end_date: ::Date.new(2023, 10, 26), closed: 0, opened: 1 },
                { date: ::Date.new(2023, 10, 27), end_date: ::Date.new(2023, 10, 31), closed: 1, opened: 1 }
              ]

              assert_equal expected, alert_trends
            end

            context "alert-centric filters" do
              test "returns only closed alerts count when resolution filter is applied" do
                repo_model = create(:soa_repository, repository: @repo)
                create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                # Alert opened before the start date and open on the end date (excluded)
                create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                # Alert opened before the start date and closed during the period
                create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"), alert_resolution: 2)

                # Code scanning with wrong tool (excluded)
                create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"), alert_resolution: 1)

                # Alert opened during the period and closed during the period
                create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"))
                create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"), alert_resolution: 2)

                # Alert opened during the period and open on the end date
                create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-03 08:00:00"))

                # Alert opened on the end date
                create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-05 08:00:00"))

                # Alert closed on the end date
                create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 6, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-05 08:00:00"), alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_resolution: 6)

                alert_trends = AlertActivityChart.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new("resolution:risk-accepted"),
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                expected = [
                  { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 0 },
                  { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 1, opened: 0 },
                  { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 0, opened: 0 },
                  { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 0 }
                ]

                assert_equal expected, alert_trends
              end

              test "returns alert counts with selected severities" do
                repo_model = create(:soa_repository, repository: @repo)
                create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                create_alert_revisions

                alert_trends = AlertActivityChart.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new("severity:critical"),
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                expected = [
                  { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 1 },
                  { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                  { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                  { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 1 }
                ]

                assert_equal expected, alert_trends
              end
            end

            context "tool-centric filters" do
              context "secret scanning filters" do
                test "returns alert counts with selected token slugs" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date (excluded)
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Code scanning with 3rd party tool (included)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"), alert_type_slug: "amazon_secret_key")
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"), alert_type_slug: "amazon_secret_key")

                  # Alert opened during the period and open on the end date
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-03 08:00:00"))

                  # Alert opened on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_type_slug: "github_token")

                  # Alert closed on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 6, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-05 08:00:00"), alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_type_slug: "amazon_secret_key")

                  alert_trends = AlertActivityChart.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("secret-scanning.secret-type:amazon_secret_key"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  expected = [
                    { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 1 },
                    { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                    { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                    { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 0 }
                  ]

                  assert_equal expected, alert_trends
                end

                test "returns alert counts with selected token providers" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date (excluded)
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Code scanning with 3rd party tool (included)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"), alert_type_provider: "Amazon AWS")
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"), alert_type_provider: "Amazon AWS")

                  # Alert opened during the period and open on the end date
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-03 08:00:00"))

                  # Alert opened on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_type_provider: "GitHub")

                  # Alert closed on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 6, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-05 08:00:00"), alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_type_provider: "Amazon AWS")

                  alert_trends = AlertActivityChart.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("secret-scanning.provider:amazon_aws"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  expected = [
                    { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 1 },
                    { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                    { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                    { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 0 }
                  ]

                  assert_equal expected, alert_trends
                end

                test "returns alert counts with selected bypassed status" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date (excluded)
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Code scanning with 3rd party tool (included)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"), alert_bypassed: true)
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"), alert_bypassed: true)

                  # Alert opened during the period and open on the end date
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-03 08:00:00"))

                  # Alert opened on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_bypassed: false)

                  # Alert closed on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 6, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-05 08:00:00"), alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_bypassed: true)

                  alert_trends = AlertActivityChart.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("secret-scanning.bypassed:true"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform


                  expected = [
                    { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 1 },
                    { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                    { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                    { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 0 }
                  ]

                  assert_equal expected, alert_trends
                end

                test "returns alert counts with selected validities" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date (excluded)
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Code scanning with 3rd party tool (included)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_UNKNOWN)
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE)

                  # Alert opened during the period and open on the end date
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-03 08:00:00"))

                  # Alert opened on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_UNKNOWN)

                  # Alert closed on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 6, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-05 08:00:00"), alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE)

                  alert_trends = AlertActivityChart.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("secret-scanning.validity:active"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  expected = [
                    { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 1 },
                    { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                    { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                    { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 0 }
                  ]

                  assert_equal expected, alert_trends
                end
              end

              context "code scanning filters" do
                test "returns alert counts with selected codeql rule" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date (excluded)
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"), rule_sarif_identifier: "rule-1")
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"), rule_sarif_identifier: "rule-1")

                  # Code scanning with 3rd party tool (excluded)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"), rule_sarif_identifier: "rule-2")
                  create(:soa_code_scanning_alert_revision, date_id: 20231004, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"), rule_sarif_identifier: "rule-2")

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"))
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"))

                  # Alert opened during the period and open on the end date
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-03 08:00:00"), rule_sarif_identifier: "rule-3")

                  # Alert opened on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-05 08:00:00"))

                  # Alert closed on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 6, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-05 08:00:00"), alert_created_at: DateTime.parse("2023-10-05 08:00:00"))

                  alert_trends = AlertActivityChart.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("codeql.rule:rule-1"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  expected = [
                    { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 0 },
                    { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 1, opened: 0 },
                    { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 0, opened: 0 },
                    { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 0, opened: 0 }
                  ]

                  assert_equal expected, alert_trends
                end

                test "returns alert counts with selected third-party rule" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date (excluded)
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"), rule_sarif_identifier: "rule-1")
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"), rule_sarif_identifier: "rule-1")

                  # Code scanning with 3rd party tool
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"), rule_sarif_identifier: "rule-2")
                  create(:soa_code_scanning_alert_revision, date_id: 20231004, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"), rule_sarif_identifier: "rule-2")

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"))
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"))

                  # Alert opened during the period and open on the end date
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-03 08:00:00"), rule_sarif_identifier: "rule-3")

                  # Alert opened on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-05 08:00:00"))

                  # Alert closed on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 6, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-05 08:00:00"), alert_created_at: DateTime.parse("2023-10-05 08:00:00"))

                  alert_trends = AlertActivityChart.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("third-party.rule:rule-2"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  expected = [
                    { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 0 },
                    { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                    { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                    { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 0, opened: 0 }
                  ]

                  assert_equal expected, alert_trends
                end
              end

              context "dependabot filters" do
                test "returns alert counts with selected package name" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date (excluded)
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Code scanning with 3rd party tool (included)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened during the period and closed during the period
                  create(:soa_dependabot_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"), package_name: "package")
                  create(:soa_dependabot_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"), package_name: "package")

                  # Alert opened during the period and open on the end date
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-03 08:00:00"))

                  # Alert opened on the end date
                  create(:soa_dependabot_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-05 08:00:00"), package_name: "package-2")

                  # Alert closed on the end date
                  create(:soa_dependabot_alert_revision, date_id: 20231005, repository: @repo, alert_number: 6, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-05 08:00:00"), alert_created_at: DateTime.parse("2023-10-05 08:00:00"), package_name: "package")

                  alert_trends = AlertActivityChart.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("dependabot.package:package"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  expected = [
                    { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 1 },
                    { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                    { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                    { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 0 }
                  ]

                  assert_equal expected, alert_trends
                end
              end
            end
          end

          context "#perform with alert_revisions_load_async" do
            test "tracks open/closed across the three tables for range less than a week with all features enabled" do
              repo_model = create(:soa_repository, repository: @repo)
              create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              create_alert_revisions

              alert_trends = AlertActivityChart.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              expected = [
                { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 1 },
                { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 2, opened: 1 },
                { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 1 }
              ]

              assert_equal expected, alert_trends
            end

            test "tracks open/closed across the three tables for range less than a week with code scanning disabled" do
              repo_model = create(:soa_repository, repository: @repo)
              create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: false, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              create_alert_revisions

              alert_trends = AlertActivityChart.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              expected = [
                { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 1 },
                { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 1 }
              ]

              assert_equal expected, alert_trends
            end

            test "tracks open/closed across the three tables for range less than a week with secret scanning disabled" do
              repo_model = create(:soa_repository, repository: @repo)
              create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: false, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              create_alert_revisions

              alert_trends = AlertActivityChart.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              expected = [
                { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 0 },
                { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 2, opened: 1 },
                { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 0, opened: 0 },
                { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 0, opened: 0 }
              ]

              assert_equal expected, alert_trends
            end

            test "tracks open/closed across the three tables for range less than a week with dependabot alerts disabled" do
              repo_model = create(:soa_repository, repository: @repo)
              create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              create_alert_revisions

              alert_trends = AlertActivityChart.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              expected = [
                { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 1 },
                { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 2, opened: 1 },
                { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 1 }
              ]

              assert_equal expected, alert_trends
            end

            test "tracks open/closed across the three tables for range less than a week with no security features provided" do
              repo_model = create(:soa_repository, repository: @repo)
              create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              create_alert_revisions

              ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                .any_instance.stubs(:selected_backend_security_features)
                .returns([])

              alert_trends = AlertActivityChart.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              expected = [
                { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 0 },
                { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 0, opened: 0 },
                { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 0, opened: 0 }
              ]

              assert_equal expected, alert_trends
            end

            test "tracks open/closed across the three tables for range greater than a week" do
              repo_model = create(:soa_repository, repository: @repo)
              create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # Alert opened before the start date and open on the end date (excluded)
              create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

              # Alert opened before the start date and closed during the period
              create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
              create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

              # Code scanning with 3rd party tool (included)
              create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231013, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
              create(:soa_code_scanning_alert_revision, date_id: 20231013, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-13 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

              # Alert opened during the period and closed during the period
              create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231014, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"))
              create(:soa_secret_scanning_alert_revision, date_id: 20231014, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-14 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"))

              # Alert opened during the period and open on the end date
              create(:soa_code_scanning_alert_revision, date_id: 20231023, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-23 08:00:00"))

              # Alert opened on the end date
              create(:soa_secret_scanning_alert_revision, date_id: 20231031, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-31 08:00:00"))

              # Alert opened on the end date + 1
              create(:soa_secret_scanning_alert_revision, date_id: 20231101, repository: @repo, alert_number: 6, alert_created_at: DateTime.parse("2023-11-01 08:00:00"))

              # Alert closed on the end date
              create(:soa_secret_scanning_alert_revision, date_id: 20231031, repository: @repo, alert_number: 7, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-31 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

              # Alert closed on the end date + 1
              create(:soa_secret_scanning_alert_revision, date_id: 20231101, repository: @repo, alert_number: 8, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-11-01 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

              alert_trends = AlertActivityChart.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 31),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              expected = [
                { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 1 },
                { date: ::Date.new(2023, 10, 6), end_date: ::Date.new(2023, 10, 9), closed: 0, opened: 0 },
                { date: ::Date.new(2023, 10, 10), end_date: ::Date.new(2023, 10, 13), closed: 1, opened: 0 },
                { date: ::Date.new(2023, 10, 14), end_date: ::Date.new(2023, 10, 17), closed: 1, opened: 0 },
                { date: ::Date.new(2023, 10, 18), end_date: ::Date.new(2023, 10, 21), closed: 0, opened: 0 },
                { date: ::Date.new(2023, 10, 22), end_date: ::Date.new(2023, 10, 26), closed: 0, opened: 1 },
                { date: ::Date.new(2023, 10, 27), end_date: ::Date.new(2023, 10, 31), closed: 1, opened: 1 }
              ]

              assert_equal expected, alert_trends
            end

            context "alert-centric filters" do
              test "returns only closed alerts count when resolution filter is applied" do
                repo_model = create(:soa_repository, repository: @repo)
                create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                # Alert opened before the start date and open on the end date (excluded)
                create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                # Alert opened before the start date and closed during the period
                create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"), alert_resolution: 2)

                # Code scanning with wrong tool (excluded)
                create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"), alert_resolution: 1)

                # Alert opened during the period and closed during the period
                create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"))
                create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"), alert_resolution: 2)

                # Alert opened during the period and open on the end date
                create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-03 08:00:00"))

                # Alert opened on the end date
                create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-05 08:00:00"))

                # Alert closed on the end date
                create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 6, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-05 08:00:00"), alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_resolution: 6)

                alert_trends = AlertActivityChart.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new("resolution:risk-accepted"),
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                expected = [
                  { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 0 },
                  { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 1, opened: 0 },
                  { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 0, opened: 0 },
                  { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 0 }
                ]

                assert_equal expected, alert_trends
              end

              test "returns alert counts with selected severities" do
                repo_model = create(:soa_repository, repository: @repo)
                create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                create_alert_revisions

                alert_trends = AlertActivityChart.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new("severity:critical"),
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                expected = [
                  { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 1 },
                  { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                  { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                  { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 1 }
                ]

                assert_equal expected, alert_trends
              end
            end

            context "tool-centric filters" do
              context "secret scanning filters" do
                test "returns alert counts with selected token slugs" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date (excluded)
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Code scanning with 3rd party tool (included)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"), alert_type_slug: "amazon_secret_key")
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"), alert_type_slug: "amazon_secret_key")

                  # Alert opened during the period and open on the end date
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-03 08:00:00"))

                  # Alert opened on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_type_slug: "github_token")

                  # Alert closed on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 6, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-05 08:00:00"), alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_type_slug: "amazon_secret_key")

                  alert_trends = AlertActivityChart.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("secret-scanning.secret-type:amazon_secret_key"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  expected = [
                    { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 1 },
                    { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                    { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                    { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 0 }
                  ]

                  assert_equal expected, alert_trends
                end

                test "returns alert counts with selected token providers" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date (excluded)
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Code scanning with 3rd party tool (included)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"), alert_type_provider: "Amazon AWS")
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"), alert_type_provider: "Amazon AWS")

                  # Alert opened during the period and open on the end date
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-03 08:00:00"))

                  # Alert opened on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_type_provider: "GitHub")

                  # Alert closed on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 6, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-05 08:00:00"), alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_type_provider: "Amazon AWS")

                  alert_trends = AlertActivityChart.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("secret-scanning.provider:amazon_aws"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  expected = [
                    { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 1 },
                    { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                    { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                    { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 0 }
                  ]

                  assert_equal expected, alert_trends
                end

                test "returns alert counts with selected bypassed status" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date (excluded)
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Code scanning with 3rd party tool (included)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"), alert_bypassed: true)
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"), alert_bypassed: true)

                  # Alert opened during the period and open on the end date
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-03 08:00:00"))

                  # Alert opened on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_bypassed: false)

                  # Alert closed on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 6, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-05 08:00:00"), alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_bypassed: true)

                  alert_trends = AlertActivityChart.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("secret-scanning.bypassed:true"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform


                  expected = [
                    { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 1 },
                    { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                    { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                    { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 0 }
                  ]

                  assert_equal expected, alert_trends
                end

                test "returns alert counts with selected validities" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date (excluded)
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Code scanning with 3rd party tool (included)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_UNKNOWN)
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE)

                  # Alert opened during the period and open on the end date
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-03 08:00:00"))

                  # Alert opened on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_UNKNOWN)

                  # Alert closed on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 6, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-05 08:00:00"), alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE)

                  alert_trends = AlertActivityChart.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("secret-scanning.validity:active"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  expected = [
                    { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 1 },
                    { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                    { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                    { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 0 }
                  ]

                  assert_equal expected, alert_trends
                end
              end

              context "code scanning filters" do
                test "returns alert counts with selected codeql rule" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date (excluded)
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"), rule_sarif_identifier: "rule-1")
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"), rule_sarif_identifier: "rule-1")

                  # Code scanning with 3rd party tool (excluded)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"), rule_sarif_identifier: "rule-2")
                  create(:soa_code_scanning_alert_revision, date_id: 20231004, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"), rule_sarif_identifier: "rule-2")

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"))
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"))

                  # Alert opened during the period and open on the end date
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-03 08:00:00"), rule_sarif_identifier: "rule-3")

                  # Alert opened on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-05 08:00:00"))

                  # Alert closed on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 6, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-05 08:00:00"), alert_created_at: DateTime.parse("2023-10-05 08:00:00"))

                  alert_trends = AlertActivityChart.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("codeql.rule:rule-1"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  expected = [
                    { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 0 },
                    { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 1, opened: 0 },
                    { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 0, opened: 0 },
                    { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 0, opened: 0 }
                  ]

                  assert_equal expected, alert_trends
                end

                test "returns alert counts with selected third-party rule" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date (excluded)
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"), rule_sarif_identifier: "rule-1")
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"), rule_sarif_identifier: "rule-1")

                  # Code scanning with 3rd party tool
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"), rule_sarif_identifier: "rule-2")
                  create(:soa_code_scanning_alert_revision, date_id: 20231004, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"), rule_sarif_identifier: "rule-2")

                  # Alert opened during the period and closed during the period
                  create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"))
                  create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"))

                  # Alert opened during the period and open on the end date
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-03 08:00:00"), rule_sarif_identifier: "rule-3")

                  # Alert opened on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-05 08:00:00"))

                  # Alert closed on the end date
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 6, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-05 08:00:00"), alert_created_at: DateTime.parse("2023-10-05 08:00:00"))

                  alert_trends = AlertActivityChart.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("third-party.rule:rule-2"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  expected = [
                    { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 0 },
                    { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                    { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                    { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 0, opened: 0 }
                  ]

                  assert_equal expected, alert_trends
                end
              end

              context "dependabot filters" do
                test "returns alert counts with selected package name" do
                  repo_model = create(:soa_repository, repository: @repo)
                  create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alert opened before the start date and open on the end date (excluded)
                  create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened before the start date and closed during the period
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Code scanning with 3rd party tool (included)
                  create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"))
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"))

                  # Alert opened during the period and closed during the period
                  create(:soa_dependabot_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"), package_name: "package")
                  create(:soa_dependabot_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"), package_name: "package")

                  # Alert opened during the period and open on the end date
                  create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-03 08:00:00"))

                  # Alert opened on the end date
                  create(:soa_dependabot_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-05 08:00:00"), package_name: "package-2")

                  # Alert closed on the end date
                  create(:soa_dependabot_alert_revision, date_id: 20231005, repository: @repo, alert_number: 6, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-05 08:00:00"), alert_created_at: DateTime.parse("2023-10-05 08:00:00"), package_name: "package")

                  alert_trends = AlertActivityChart.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("dependabot.package:package"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  expected = [
                    { date: ::Date.new(2023, 10, 2), end_date: ::Date.new(2023, 10, 2), closed: 0, opened: 1 },
                    { date: ::Date.new(2023, 10, 3), end_date: ::Date.new(2023, 10, 3), closed: 0, opened: 0 },
                    { date: ::Date.new(2023, 10, 4), end_date: ::Date.new(2023, 10, 4), closed: 1, opened: 0 },
                    { date: ::Date.new(2023, 10, 5), end_date: ::Date.new(2023, 10, 5), closed: 1, opened: 0 }
                  ]

                  assert_equal expected, alert_trends
                end
              end
            end
          end

          def create_alert_revisions
            # Set up sequence of datetimes that are spaced 1 second apart to test slicing
            # of the alert revisions by date
            now = Time.now
            datetime_sequence =
              (1..8).map do |i|
                (now + i.seconds).freeze
              end.freeze

            # Alert opened before the start date and open on the end date (excluded)
            create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 1, alert_severity: "moderate", alert_created_at: DateTime.parse("2023-10-01 08:00:00"), updated_at: datetime_sequence[0])

            # Alert opened before the start date and closed during the period
            create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "CodeQL", alert_severity: "high", repository: @repo, alert_number: 2, alert_created_at: DateTime.parse("2023-10-01 08:00:00"), updated_at: datetime_sequence[1])
            create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", repository: @repo, tool: "CodeQL", alert_number: 2, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"), updated_at: datetime_sequence[2])

            # Code scanning with 3rd party tool (included)
            create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231003, tool: "not-code-ql", alert_severity: "high", repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-01 08:00:00"), updated_at: datetime_sequence[3])
            create(:soa_code_scanning_alert_revision, date_id: 20231003, alert_severity: "high", tool: "not-code-ql", repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-03 08:00:00"), alert_created_at: DateTime.parse("2023-10-01 08:00:00"), updated_at: datetime_sequence[4])

            # Alert opened during the period and closed during the period
            create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231004, repository: @repo, alert_number: 3, alert_created_at: DateTime.parse("2023-10-02 08:00:00"))
            create(:soa_secret_scanning_alert_revision, date_id: 20231004, repository: @repo, alert_number: 3, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-04 08:00:00"), alert_created_at: DateTime.parse("2023-10-02 08:00:00"), updated_at: datetime_sequence[5])

            # Alert opened during the period and open on the end date
            create(:soa_code_scanning_alert_revision, date_id: 20231003, repository: @repo, alert_severity: "low", alert_number: 4, alert_created_at: DateTime.parse("2023-10-03 08:00:00"), updated_at: datetime_sequence[6])

            # Alert opened on the end date
            create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 5, alert_created_at: DateTime.parse("2023-10-05 08:00:00"), updated_at: datetime_sequence[7])

            # Alert closed on the end date
            create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: @repo, alert_number: 6, alert_resolved: true, alert_resolved_at: DateTime.parse("2023-10-05 08:00:00"), alert_created_at: DateTime.parse("2023-10-05 08:00:00"), updated_at: datetime_sequence[8])
          end
        end
      end
    end
  end
end
