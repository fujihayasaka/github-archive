# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class ReopenedAlertsTest < GitHub::TestCase
          VALID_SECURITY_FEATURES = %w[dependabot_alerts secret_scanning codeql]
          QueryParser = ::Search::Queries::SecurityCenter::QueryParser
          TokenValidity = SecretScanningAlertRevision::SecretScanningTokenValidity

          fixtures do
            @biz = create(:business)
            @org_admin = create(:user)
            @user_session = create(:user_session, user: @org_admin)
            @org = create(:organization, business: @biz, admin: @org_admin)
          end

          setup do
            ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
              .any_instance.stubs(:selected_backend_security_features)
              .returns(VALID_SECURITY_FEATURES)
          end

          context "perform" do
            test "returns number of reopened alerts for available features" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # Alerts resolved before the period but got reopened during the period
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))

              # Alerts already resolved during the period and got reopened during the period
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

              # Alerts reopened, resolved, then reopened again during the period (only the last one is counted)
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231002, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231002, next_revision_date_id: 20231003, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 2), alert_created_at: ::Date.new(2023, 9, 30))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

              # Alerts reopened before the start of the period (excluded)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))

              reopened_alerts = ReopenedAlerts.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              assert_equal 5, reopened_alerts
            end

            test "returns 0 when no security_features are available" do
              ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                .any_instance.stubs(:selected_backend_security_features)
                .returns([])

              reopened_alerts = ReopenedAlerts.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              assert_equal 0, reopened_alerts
            end

            context "tool-centric filters" do
              context "dependabot filters" do
                test "returns number of reopened alerts with selected package names" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alerts resolved before the period but got reopened during the period
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30), package_name: "package")
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), package_name: "package")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts already resolved during the period and got reopened during the period
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), package_name: "package")
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30), package_name: "package")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened, resolved, then reopened again during the period (only the last one is counted)
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231002, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231002, next_revision_date_id: 20231003, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 2), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened before the start of the period (excluded)
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231001, alert_number: 4, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))

                  reopened_alerts = ReopenedAlerts.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("dependabot.package:package"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  assert_equal 2, reopened_alerts
                end
              end

              context "code scanning filters" do
                test "returns number of reopened alerts with selected rule ids" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alerts resolved before the period but got reopened during the period
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30), rule_sarif_identifier: "some-rule")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), rule_sarif_identifier: "some-rule")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts already resolved during the period and got reopened during the period
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), rule_sarif_identifier: "some-rule")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30), rule_sarif_identifier: "some-rule")
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened, resolved, then reopened again during the period (only the last one is counted)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231002, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231002, next_revision_date_id: 20231003, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 2), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened before the start of the period (excluded)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231001, alert_number: 4, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))

                  reopened_alerts = ReopenedAlerts.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("codeql.rule:some-rule"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  assert_equal 2, reopened_alerts
                end
              end

              context "secret scanning filters" do
                test "returns number of reopened alerts with selected validities" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alerts resolved before the period but got reopened during the period
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30), alert_validity: TokenValidity::TOKEN_VALIDITY_ACTIVE)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_validity: TokenValidity::TOKEN_VALIDITY_ACTIVE)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts already resolved during the period and got reopened during the period
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_validity: TokenValidity::TOKEN_VALIDITY_ACTIVE)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30), alert_validity: TokenValidity::TOKEN_VALIDITY_ACTIVE)
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened, resolved, then reopened again during the period (only the last one is counted)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231002, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231002, next_revision_date_id: 20231003, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 2), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened before the start of the period (excluded)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, alert_number: 4, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))

                  reopened_alerts = ReopenedAlerts.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("secret-scanning.validity:active"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  assert_equal 2, reopened_alerts
                end

                test "returns number of reopened alerts with selected bypassed statuses" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alerts resolved before the period but got reopened during the period
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30), alert_bypassed: true)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_bypassed: true)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts already resolved during the period and got reopened during the period
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_bypassed: true)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30), alert_bypassed: true)
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened, resolved, then reopened again during the period (only the last one is counted)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231002, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231002, next_revision_date_id: 20231003, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 2), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened before the start of the period (excluded)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, alert_number: 4, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))

                  reopened_alerts = ReopenedAlerts.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("secret-scanning.bypassed:true"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  assert_equal 2, reopened_alerts
                end

                test "returns number of reopened alerts with selected token types" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alerts resolved before the period but got reopened during the period
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30), alert_type_slug: "amazon_access_key")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_type_slug: "amazon_access_key")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts already resolved during the period and got reopened during the period
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_type_slug: "amazon_access_key")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30), alert_type_slug: "amazon_access_key")
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened, resolved, then reopened again during the period (only the last one is counted)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231002, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30), alert_type_slug: "github_token")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231002, next_revision_date_id: 20231003, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 2), alert_created_at: ::Date.new(2023, 9, 30), alert_type_slug: "github_token")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_type_slug: "github_token")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30), alert_type_slug: "github_token")

                  # Alerts reopened before the start of the period (excluded)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, alert_number: 4, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))

                  reopened_alerts = ReopenedAlerts.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("secret-scanning.secret-type:amazon_access_key"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  assert_equal 2, reopened_alerts
                end

                test "returns number of reopened alerts with selected token providers" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alerts resolved before the period but got reopened during the period
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30), alert_type_provider: "Amazon AWS")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_type_provider: "Amazon AWS")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts already resolved during the period and got reopened during the period
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_type_provider: "Amazon AWS")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30), alert_type_provider: "Amazon AWS")
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened, resolved, then reopened again during the period (only the last one is counted)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231002, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30), alert_type_provider: "GitHub")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231002, next_revision_date_id: 20231003, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 2), alert_created_at: ::Date.new(2023, 9, 30), alert_type_provider: "GitHub")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_type_provider: "GitHub")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30), alert_type_provider: "GitHub")

                  # Alerts reopened before the start of the period (excluded)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, alert_number: 4, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))

                  reopened_alerts = ReopenedAlerts.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("secret-scanning.provider:amazon_aws"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform
                  assert_equal 2, reopened_alerts
                end
              end
            end
          end

          context "perform with alert_revisions_load_async" do
            test "returns number of reopened alerts for available features" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # Alerts resolved before the period but got reopened during the period
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))

              # Alerts already resolved during the period and got reopened during the period
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

              # Alerts reopened, resolved, then reopened again during the period (only the last one is counted)
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231002, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231002, next_revision_date_id: 20231003, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 2), alert_created_at: ::Date.new(2023, 9, 30))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

              # Alerts reopened before the start of the period (excluded)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))

              reopened_alerts = ReopenedAlerts.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              assert_equal 5, reopened_alerts
            end

            test "returns 0 when no security_features are available" do
              ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                .any_instance.stubs(:selected_backend_security_features)
                .returns([])

              reopened_alerts = ReopenedAlerts.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              assert_equal 0, reopened_alerts
            end

            context "tool-centric filters" do
              context "dependabot filters" do
                test "returns number of reopened alerts with selected package names" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alerts resolved before the period but got reopened during the period
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30), package_name: "package")
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), package_name: "package")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts already resolved during the period and got reopened during the period
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), package_name: "package")
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30), package_name: "package")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened, resolved, then reopened again during the period (only the last one is counted)
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231002, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231002, next_revision_date_id: 20231003, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 2), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened before the start of the period (excluded)
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231001, alert_number: 4, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))

                  reopened_alerts = ReopenedAlerts.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("dependabot.package:package"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  assert_equal 2, reopened_alerts
                end
              end

              context "code scanning filters" do
                test "returns number of reopened alerts with selected rule ids" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alerts resolved before the period but got reopened during the period
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30), rule_sarif_identifier: "some-rule")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), rule_sarif_identifier: "some-rule")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts already resolved during the period and got reopened during the period
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), rule_sarif_identifier: "some-rule")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30), rule_sarif_identifier: "some-rule")
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened, resolved, then reopened again during the period (only the last one is counted)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231002, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231002, next_revision_date_id: 20231003, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 2), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened before the start of the period (excluded)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231001, alert_number: 4, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))

                  reopened_alerts = ReopenedAlerts.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("codeql.rule:some-rule"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  assert_equal 2, reopened_alerts
                end
              end

              context "secret scanning filters" do
                test "returns number of reopened alerts with selected validities" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alerts resolved before the period but got reopened during the period
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30), alert_validity: TokenValidity::TOKEN_VALIDITY_ACTIVE)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_validity: TokenValidity::TOKEN_VALIDITY_ACTIVE)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts already resolved during the period and got reopened during the period
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_validity: TokenValidity::TOKEN_VALIDITY_ACTIVE)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30), alert_validity: TokenValidity::TOKEN_VALIDITY_ACTIVE)
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened, resolved, then reopened again during the period (only the last one is counted)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231002, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231002, next_revision_date_id: 20231003, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 2), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened before the start of the period (excluded)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, alert_number: 4, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))

                  reopened_alerts = ReopenedAlerts.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("secret-scanning.validity:active"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  assert_equal 2, reopened_alerts
                end

                test "returns number of reopened alerts with selected bypassed statuses" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alerts resolved before the period but got reopened during the period
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30), alert_bypassed: true)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_bypassed: true)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts already resolved during the period and got reopened during the period
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_bypassed: true)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30), alert_bypassed: true)
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened, resolved, then reopened again during the period (only the last one is counted)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231002, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231002, next_revision_date_id: 20231003, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 2), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened before the start of the period (excluded)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, alert_number: 4, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))

                  reopened_alerts = ReopenedAlerts.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("secret-scanning.bypassed:true"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  assert_equal 2, reopened_alerts
                end

                test "returns number of reopened alerts with selected token types" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alerts resolved before the period but got reopened during the period
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30), alert_type_slug: "amazon_access_key")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_type_slug: "amazon_access_key")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts already resolved during the period and got reopened during the period
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_type_slug: "amazon_access_key")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30), alert_type_slug: "amazon_access_key")
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened, resolved, then reopened again during the period (only the last one is counted)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231002, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30), alert_type_slug: "github_token")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231002, next_revision_date_id: 20231003, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 2), alert_created_at: ::Date.new(2023, 9, 30), alert_type_slug: "github_token")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_type_slug: "github_token")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30), alert_type_slug: "github_token")

                  # Alerts reopened before the start of the period (excluded)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, alert_number: 4, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))

                  reopened_alerts = ReopenedAlerts.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("secret-scanning.secret-type:amazon_access_key"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  assert_equal 2, reopened_alerts
                end

                test "returns number of reopened alerts with selected token providers" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Alerts resolved before the period but got reopened during the period
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30), alert_type_provider: "Amazon AWS")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_type_provider: "Amazon AWS")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts already resolved during the period and got reopened during the period
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_type_provider: "Amazon AWS")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30), alert_type_provider: "Amazon AWS")
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30))
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30))

                  # Alerts reopened, resolved, then reopened again during the period (only the last one is counted)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231002, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30), alert_type_provider: "GitHub")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231002, next_revision_date_id: 20231003, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 2), alert_created_at: ::Date.new(2023, 9, 30), alert_type_provider: "GitHub")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, next_revision_date_id: 20231004, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), alert_type_provider: "GitHub")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 3, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 9, 30), alert_type_provider: "GitHub")

                  # Alerts reopened before the start of the period (excluded)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, alert_number: 4, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30))

                  reopened_alerts = ReopenedAlerts.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("secret-scanning.provider:amazon_aws"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform
                  assert_equal 2, reopened_alerts
                end
              end
            end

            test "returns correct data when alerts are stored in different slices" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              updated_at = Time.now
              # Slices are using floor(`updated_at`) to calculate, so adding a second to make sure they are in different slices
              updated_at_2 = updated_at + 1.second

              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30), updated_at: updated_at)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 1, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), updated_at: updated_at)

              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 9, 30), updated_at: updated_at_2)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 2, alert_resolved: false, alert_reopened_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 9, 30), updated_at: updated_at_2)

              reopened_alerts = ReopenedAlerts.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              assert_equal 2, reopened_alerts
            end
          end
        end
      end
    end
  end
end
