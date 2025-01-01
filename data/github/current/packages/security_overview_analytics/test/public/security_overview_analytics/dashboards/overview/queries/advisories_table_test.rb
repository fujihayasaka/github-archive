# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AdvisoriesTableTest < GitHub::TestCase
          VALID_SECURITY_FEATURES = %w[dependabot_alerts secret_scanning codeql]
          QueryParser = ::Search::Queries::SecurityCenter::QueryParser

          fixtures do
            @biz = create(:business)
            @org_admin = create(:user)
            @user_session = create(:user_session, user: @org_admin)
            @org = create(:organization, business: @biz, admin: @org_admin)
            @repo = create(:private_repository, owner: @org)
            @repo1 = create(:private_repository, owner: @org)
            @repo2 = create(:private_repository, owner: @org)

            @repo1_model = create(:soa_repository, repository: @repo1)
            @repo2_model = create(:soa_repository, repository: @repo2)
          end

          setup do
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_class?).returns(true)
            ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
              .any_instance.stubs(:selected_backend_security_features)
              .returns(%w[dependabot_alerts secret_scanning codeql])
          end

          context "#perform" do
            test "filters to alerts that are open in the date range" do
              repo_model = create(:soa_repository, repository: @repo)
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # Alert open on the end date (included).
              create(:soa_dependabot_alert_revision, date_id: 20231006, repository: @repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 1))

              # Alert open on end date and closed after end date.
              create(:soa_dependabot_alert_revision, date_id: 20231002, next_revision_date_id: 20231008, repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, date_id: 20231008, repository: @repo, alert_number: 2, alert_resolved: true, alert_created_at: ::Date.new(2023, 10, 2))

              # Alert closed on the end date (should be excluded from results).
              create(:soa_dependabot_alert_revision, date_id: 20231002, repository: @repo, alert_number: 3, alert_resolved: true, alert_created_at: ::Date.new(2023, 10, 2))

              # Alert opened before start date (included).
              create(:soa_dependabot_alert_revision, date_id: 20231001, repository: @repo, alert_number: 4, alert_created_at: ::Date.new(2023, 10, 1))

              expected = [{ ghsa_id: "GHSA-1234-5678-90AB", open_alerts: 2 }]

              repos = AdvisoriesTable.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 8),
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              ).perform

              assert_same_elements(expected, repos)
            end

            test "filters out repos with feature disabled" do
              repo1 = create(:private_repository, owner: @org)
              repo2 = create(:private_repository, owner: @org)

              repo1_model = create(:soa_repository, repository: repo1)
              repo2_model = create(:soa_repository, repository: repo2)

              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo1_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo2_model, date_id: 20231001, dependabot_alerts_enabled: false, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              create(:soa_dependabot_alert_revision, date_id: 20231006, repository: repo1, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_dependabot_alert_revision, date_id: 20231006, repository: repo2, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))

              repos_filterer = OrgReposFilterer.new(organization: @org, query: QueryParser.new, user: @org.owner, user_session: @user_session)
              alerts_filterer = AlertsFilterer.new(query: QueryParser.new, scope: @org, user: @org_admin)

              expected = [{ ghsa_id: "GHSA-1234-5678-90AB", open_alerts: 1 }]

              repos = AdvisoriesTable.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 7),
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              ).perform

              assert_same_elements(expected, repos)
            end

            test "returns empty when no security_features are available" do
              ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                .any_instance.stubs(:selected_backend_security_features)
                .returns([])

              repos = AdvisoriesTable.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 7),
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              ).perform

              assert_empty(repos)
            end

            context "alert-centric filters" do
              test "returns no result when resolution filter is applied" do
                create_dbot_alert_revisions

                repos = AdvisoriesTable.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new("resolution:risk-accepted"),
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 7),
                  user_session: @user_session,
                  return_alert_count: false,
                  is_open_selected: true,
                ).perform

                assert_empty repos
              end

              test "returns alert counts filtered to the selected severities" do
                create_dbot_alert_revisions_with_metadata

                expected = [{ ghsa_id: "GHSA-1234-5678-90AB", open_alerts: 2 }]

                repos = AdvisoriesTable.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new("severity:low"),
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 7),
                  user_session: @user_session,
                  return_alert_count: false,
                  is_open_selected: true,
                ).perform

                assert_same_elements(expected, repos)
              end
            end

            context "tool-centric filters" do
              context "dependabot filters" do
                test "returns alert counts filtered to the selected ecosystem" do
                  create_dbot_alert_revisions_with_metadata

                  expected = [{ ghsa_id: "GHSA-1234-5678-90AB", open_alerts: 2 }]

                  repos = AdvisoriesTable.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("dependabot.ecosystem:npm"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 7),
                    user_session: @user_session,
                    return_alert_count: false,
                    is_open_selected: true,
                  ).perform

                  assert_same_elements(expected, repos)
                end

                test "returns alert counts filtered to the selected package" do
                  create_dbot_alert_revisions_with_metadata

                  expected = [{ ghsa_id: "GHSA-1234-5678-90AB", open_alerts: 1 }]

                  repos = AdvisoriesTable.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("dependabot.package:package-2"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 7),
                    user_session: @user_session,
                    return_alert_count: false,
                    is_open_selected: true,
                  ).perform

                  assert_same_elements(expected, repos)
                end

                test "returns alert counts filtered to the selected scope" do
                  create_dbot_alert_revisions_with_metadata

                  expected = [{ ghsa_id: "GHSA-1234-5678-90AB", open_alerts: 1 }]

                  repos = AdvisoriesTable.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("dependabot.scope:development"),
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 7),
                    user_session: @user_session,
                    return_alert_count: false,
                    is_open_selected: true,
                  ).perform

                  assert_same_elements(expected, repos)
                end
              end

              test "returns no result when tool filter other than dependabot is applied" do
                create_dbot_alert_revisions

                repos = AdvisoriesTable.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new("secret-scanning.validity:active"),
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 7),
                  user_session: @user_session,
                  return_alert_count: false,
                  is_open_selected: true,
                ).perform

                assert_empty repos

                repos = AdvisoriesTable.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new("codeql.rule:rule/some-rule"),
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 7),
                  user_session: @user_session,
                  return_alert_count: false,
                  is_open_selected: true,
                ).perform

                assert_empty repos
              end
            end
          end

          def create_dbot_alert_revisions
            create(:security_overview_analytics_feature_status_revision, repository_metadata: @repo1_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
            create(:security_overview_analytics_feature_status_revision, repository_metadata: @repo2_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

            create(:soa_dependabot_alert_revision, date_id: 20231006, repository: @repo1, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 1))
            create(:soa_dependabot_alert_revision, date_id: 20231006, repository: @repo2, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
          end

          def create_dbot_alert_revisions_with_metadata
            create(:security_overview_analytics_feature_status_revision, repository_metadata: @repo1_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
            create(:security_overview_analytics_feature_status_revision, repository_metadata: @repo2_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

            create(:soa_dependabot_alert_revision, date_id: 20231006, repository: @repo1, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 1), alert_severity: "low", ecosystem: "npm", package_name: "package-1", dependency_scope: "runtime")
            create(:soa_dependabot_alert_revision, date_id: 20231006, repository: @repo2, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1), alert_severity: "low", ecosystem: "npm", package_name: "package-1", dependency_scope: "runtime")
            create(:soa_dependabot_alert_revision, date_id: 20231006, repository: @repo2, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 1), alert_severity: "high", ecosystem: "pip", package_name: "package-2", dependency_scope: "development")
          end
        end
      end
    end
  end
end
