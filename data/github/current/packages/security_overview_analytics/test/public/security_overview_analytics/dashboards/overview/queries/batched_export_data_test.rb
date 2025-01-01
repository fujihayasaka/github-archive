# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class BatchedExportDataTest < GitHub::TestCase
          VALID_SECURITY_FEATURES = %w[dependabot_alerts secret_scanning codeql some-tool]
          QueryParser = ::Search::Queries::SecurityCenter::QueryParser

          fixtures do
            @biz = create(:business)
            @org_admin = create(:user)
            @user_session = create(:user_session, user: @org_admin)
            @org = create(:organization, business: @biz, admin: @org_admin)
            @date = create(:security_overview_analytics_date)
            @repo = create(:private_repository, owner: @org).tap do |repo|
              repo_metadata = create(:security_overview_analytics_repository, repository: repo)
              create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_metadata, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
            end

          end

          setup do
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_for_resolution?).returns(true)
          end

          context "#perform" do
            test "returns alert data" do
              # 5 days old
              dd = create(:soa_dependabot_alert_revision, date_id: 20230928, next_revision_date_id: 20230930, repository: @repo, alert_number: 1, alert_created_at: ::Date.new(2023, 9, 30))
              dd_latest = create(:soa_dependabot_alert_revision, date_id: 20230930, next_revision_date_id: 20231006, repository: @repo, alert_number: 1, alert_created_at: ::Date.new(2023, 9, 30))
              # 4 days old
              ss = create(:soa_secret_scanning_alert_revision, date_id: 20230928, next_revision_date_id: 20230930, repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
              ss_latest = create(:soa_secret_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231006, repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
              # 3 days old
              cs = create(:soa_code_scanning_alert_revision, date_id: 20230928, next_revision_date_id: 20230930, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))
              cs_latest = create(:soa_code_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))

              query = QueryParser.new("")

              repos_filterer = ::SecurityOverviewAnalytics::Dashboards::OrgReposFilterer.new(
                allowed_repo_ids_by_feature: nil,
                organization: @org,
                query:,
                user: @org_admin,
                user_session: @user_session,
              )

              alerts_filterer = ::SecurityOverviewAnalytics::Dashboards::AlertsFilterer.new(
                query:,
                scope: @org,
                user: @org_admin
              )

              data = T.let([], T::Array[T.untyped])
              [
                ["codeql"],
                [::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS],
                [::SecurityCenter::SecurityFeatures::SECRET_SCANNING],
              ].each do |feature|
                data << BatchedExportData.new(
                  user: @org_admin,
                  query_parser: query,
                  alerts_filterer:,
                  repos_filterer:,
                  scope: @org,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  security_features: feature,
                  authorized_orgs_by_feature: nil,
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform.take
              end

              assert_equal(3, data.size)

              row = data[0]
              refute_nil row
              assert_equal row["id"], cs_latest.id
              assert_equal row["tool"], "CodeQL"
              assert_equal row["alert_severity"], cs_latest.alert_severity
              assert_nil row["alert_bypassed"]
              assert_nil row["alert_type"]
              assert_nil row["alert_type_provider"]
              assert_nil row["alert_validity"]
              assert_nil row["ghsa_id"]
              assert_nil row["ecosystem"]
              assert_nil row["package_name"]
              assert_nil row["dependency_scope"]
              assert_equal row["rule_sarif_identifier"], cs_latest.rule_sarif_identifier
              assert_equal row["name"], @repo.name
              assert_equal row["visibility"], 1
              assert_equal row["alert_number"], cs_latest.alert_number
              assert_equal row["alert_created_at"], cs_latest.alert_created_at
              assert_nil row["alert_resolved_at"]
              assert_nil row["alert_reopened_at"]
              assert_nil row["alert_resolution"]

              row = data[1]
              refute_nil row
              assert_equal row["id"], dd_latest.id
              assert_equal row["tool"], "dependabot"
              assert_equal row["alert_severity"], dd.alert_severity
              assert_nil row["alert_bypassed"]
              assert_nil row["alert_type"]
              assert_nil row["alert_type_provider"]
              assert_nil row["alert_validity"]
              assert_equal row["ghsa_id"], dd_latest.ghsa_id
              assert_equal row["ecosystem"], dd_latest.ecosystem
              assert_equal row["package_name"], dd_latest.package_name
              assert_equal row["dependency_scope"], dd_latest.dependency_scope
              assert_nil row["rule_sarif_identifier"]
              assert_equal row["name"], @repo.name
              assert_equal row["visibility"], 1
              assert_equal row["alert_number"], dd_latest.alert_number
              assert_equal row["alert_created_at"], dd_latest.alert_created_at
              assert_nil row["alert_resolved_at"]
              assert_nil row["alert_reopened_at"]
              assert_nil row["alert_resolution"]

              row = data[2]
              refute_nil row
              assert_equal row["id"], ss_latest.id
              assert_equal row["tool"], "secret-scanning"
              assert_equal row["alert_severity"], "critical"
              assert_equal row["alert_bypassed"], false
              assert_equal row["alert_type"], ss_latest.alert_type
              assert_equal row["alert_type_provider"], ss_latest.alert_type_provider
              assert_equal row["alert_validity"], 0
              assert_nil row["ghsa_id"]
              assert_nil row["ecosystem"]
              assert_nil row["package_name"]
              assert_nil row["dependency_scope"]
              assert_nil row["rule_sarif_identifier"]
              assert_equal row["name"], @repo.name
              assert_equal row["visibility"], 1
              assert_equal row["alert_number"], ss_latest.alert_number
              assert_equal row["alert_created_at"], ss_latest.alert_created_at
              assert_nil row["alert_resolved_at"]
              assert_nil row["alert_reopened_at"]
              assert_nil row["alert_resolution"]
            end

            test "returns alert data when tool-centric filters present" do
              # 5 days old
              dd = create(:soa_dependabot_alert_revision, date_id: 20230928, next_revision_date_id: 20230930, repository: @repo, alert_number: 1, alert_created_at: ::Date.new(2023, 9, 30))
              dd_latest = create(:soa_dependabot_alert_revision, date_id: 20230930, next_revision_date_id: 20231006, repository: @repo, alert_number: 1, alert_created_at: ::Date.new(2023, 9, 30))
              # 4 days old
              ss = create(:soa_secret_scanning_alert_revision, date_id: 20230928, next_revision_date_id: 20230930, repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
              ss_latest = create(:soa_secret_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231006, repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
              # valid secret
              ss_valid = create(:soa_secret_scanning_alert_revision, date_id: 20230928, next_revision_date_id: 20230930, repository: @repo, alert_number: 4, alert_created_at: ::Date.new(2023, 10, 1), alert_validity: 1)
              ss_valid_latest = create(:soa_secret_scanning_alert_revision, date_id: 20231001, next_revision_date_id: SecurityOverviewAnalytics::Date::FUTURE_DATE_ID, repository: @repo, alert_number: 4, alert_created_at: ::Date.new(2023, 10, 1), alert_validity: 1)
              # 3 days old
              cs = create(:soa_code_scanning_alert_revision, date_id: 20230928, next_revision_date_id: 20230930, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))
              cs_latest = create(:soa_code_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))

              query = QueryParser.new("secret-scanning.validity:active")

              repos_filterer = ::SecurityOverviewAnalytics::Dashboards::OrgReposFilterer.new(
                allowed_repo_ids_by_feature: nil,
                organization: @org,
                query:,
                user: @org_admin,
                user_session: @user_session,
              )

              alerts_filterer = ::SecurityOverviewAnalytics::Dashboards::AlertsFilterer.new(
                query:,
                scope: @org,
                user: @org_admin
              )

              data = T.let([], T::Array[T.untyped])
              [
                ["codeql"],
                [::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS],
                [::SecurityCenter::SecurityFeatures::SECRET_SCANNING],
              ].each do |feature|
                data << BatchedExportData.new(
                  user: @org_admin,
                  query_parser: query,
                  alerts_filterer:,
                  repos_filterer:,
                  scope: @org,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  security_features: feature,
                  authorized_orgs_by_feature: nil,
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform.take
              end

              assert_equal 1, data.compact.size
              row = data.compact[0]
              refute_nil row
              assert_equal row["id"], ss_valid_latest.id
              assert_equal row["tool"], "secret-scanning"
              assert_equal row["alert_severity"], "critical"
              assert_equal row["alert_bypassed"], false
              assert_equal row["alert_type"], ss_valid_latest.alert_type
              assert_equal row["alert_type_provider"], ss_valid_latest.alert_type_provider
              assert_equal row["alert_validity"], 1
              assert_nil row["ghsa_id"]
              assert_nil row["ecosystem"]
              assert_nil row["package_name"]
              assert_nil row["dependency_scope"]
              assert_nil row["rule_sarif_identifier"]
              assert_equal row["name"], @repo.name
              assert_equal row["visibility"], 1
              assert_equal row["alert_number"], ss_valid_latest.alert_number
              assert_equal row["alert_created_at"], ss_valid_latest.alert_created_at
              assert_nil row["alert_resolved_at"]
              assert_nil row["alert_reopened_at"]
              assert_nil row["alert_resolution"]
            end
          end
        end
      end
    end
  end
end
