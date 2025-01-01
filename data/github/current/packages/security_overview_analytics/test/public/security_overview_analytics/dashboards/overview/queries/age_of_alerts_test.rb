# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AgeOfAlertsTest < GitHub::TestCase
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
              repo_metadata
            end
          end

          setup do
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_for_resolution?).returns(true)
            ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
              .any_instance.stubs(:selected_backend_security_features)
              .returns(VALID_SECURITY_FEATURES)
          end

          test "returns the average age of all alerts when not all features have data" do
            # only make secret scanning revisions
            # 5 days old
            create(:soa_secret_scanning_alert_revision, date_id: 20230930, next_revision_date_id: 20231006, repository: @repo, alert_number: 1, alert_created_at: ::Date.new(2023, 9, 30))
            # 4 days old
            create(:soa_secret_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231006, repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
            # 3 days old
            create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))

            avg = AgeOfAlerts.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(4, avg.value)
            assert_equal(3, avg.alert_count)
          end

          test "returns the average age of all alerts when all features have data" do
            # 5 days old
            create(:soa_secret_scanning_alert_revision, date_id: 20230930, next_revision_date_id: 20231006, repository: @repo, alert_number: 1, alert_created_at: ::Date.new(2023, 9, 30))
            # 4 days old
            create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231006, repository: @repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 1))
            # 3 days old
            create(:soa_dependabot_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: @repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 2))

            avg = AgeOfAlerts.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(4, avg.value)
            assert_equal(3, avg.alert_count)
          end

          test "returns the average age of some alerts when not all features are enabled" do
            repo = create(:private_repository, owner: @org).tap do |repo|
              repo_metadata = create(:security_overview_analytics_repository, repository: repo)
              create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_metadata,
                dependabot_alerts_enabled: true, code_scanning_enabled: false, secret_scanning_enabled: false,
                secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
              repo_metadata
            end

            # 5 days old
            create(:soa_secret_scanning_alert_revision, date_id: 20230930, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 9, 30))
            # 4 days old
            create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 1))
            # 3 days old
            create(:soa_dependabot_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 2))

            stub_can_view_all_alerts(false)
            SecurityCenter::AuthorizationEnumerator
              .any_instance
              .expects(:allowed_repository_ids_by_feature_for_organization_member)
              .returns({
                "code_scanning" => [[repo.id], false],
                "dependabot_alerts" => [[repo.id], false],
                "secret_scanning" => [[repo.id], false],
              })

            avg = AgeOfAlerts.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(3, avg.value)
            assert_equal(1, avg.alert_count)
          end

          test "returns 0 when all features are disabled" do
            repo = create(:private_repository, owner: @org).tap do |repo|
              repo_metadata = create(:security_overview_analytics_repository, repository: repo)
              create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_metadata,
                dependabot_alerts_enabled: false, code_scanning_enabled: false, secret_scanning_enabled: false,
                secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
              repo_metadata
            end

            # 5 days old
            create(:soa_secret_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 1))
            # 4 days old
            create(:soa_code_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 2))
            # 3 days old
            create(:soa_dependabot_alert_revision, date_id: 20231003, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 3))

            stub_can_view_all_alerts(false)
            SecurityCenter::AuthorizationEnumerator
              .any_instance
              .expects(:allowed_repository_ids_by_feature_for_organization_member)
              .returns({
                "code_scanning" => [[repo.id], false],
                "dependabot_alerts" => [[repo.id], false],
                "secret_scanning" => [[repo.id], false],
              })

            avg = AgeOfAlerts.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(0, avg.value)
            assert_equal(0, avg.alert_count)
          end

          context "when no features are selected" do
            test "it returns 0" do
              SecurityProduct::Permissions::OrgAuthz.stubs(:can_manage_security_products?).returns(true)

              avg = AgeOfAlerts.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
                ).perform

              assert_equal(0, avg.value)
              assert_equal(0, avg.alert_count)
            end
          end

          test "uses the most recent alert revision <= period end date" do
            # closed alert:
            # 5 days old
            create(
              :soa_secret_scanning_alert_revision,
              date_id: 20230930,
              next_revision_date_id: 20231003,
              repository: @repo,
              alert_number: 1,
              alert_created_at: ::Date.new(2023, 9, 30),
              alert_resolved: true
            )

            # reopened alert: this is the revision that should be used. Setting alert_created_at to be different so that we can tell.
            # 3 days old
            create(
              :soa_secret_scanning_alert_revision,
              date_id: 20231002,
              next_revision_date_id: 20231006,
              repository: @repo,
              alert_number: 1,
              alert_created_at: ::Date.new(2023, 10, 2)
            )

            # after period end date
            # 5 days old
            create(
              :soa_secret_scanning_alert_revision,
              date_id: 20231006,
              alert_number: 1,
              alert_created_at: ::Date.new(2023, 9, 30)
            )

            avg = AgeOfAlerts.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(3, avg.value)
            assert_equal(1, avg.alert_count)
          end

          test "only open alerts are included in the average" do
            create(
              :soa_secret_scanning_alert_revision,
              date_id: 20231001,
              repository: @repo,
              alert_number: 1,
              alert_created_at: ::Date.new(2023, 10, 1),
              alert_resolved: true
            )

            avg = AgeOfAlerts.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(0, avg.value)
            assert_equal(0, avg.alert_count)
          end

          test "alerts created before the time period are included" do
            create(
              :soa_secret_scanning_alert_revision,
              date_id: 20231001,
              repository: @repo,
              alert_number: 1,
              alert_created_at: ::Date.new(2023, 10, 1)
            )

            avg = AgeOfAlerts.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(4, avg.value)
            assert_equal(1, avg.alert_count)
          end

          test "alerts at the end of previous day are counted correctly" do
            create(
              :soa_secret_scanning_alert_revision,
              date_id: 20231001,
              repository: @repo,
              alert_number: 1,
              # Alerts created in previous day are correctly attributed to it
              # This tests storage of time in mysql server timezone and not UTC
              alert_created_at: ::DateTime.new(2023, 10, 1).ago(1.hour)
            )

            avg = AgeOfAlerts.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(5, avg.value)
            assert_equal(1, avg.alert_count)
          end

          test "rounds the average to the nearest integer" do
            # 5 days before end date
            create(
              :soa_secret_scanning_alert_revision,
              date_id: 20230930,
              repository: @repo,
              alert_number: 1,
              alert_created_at: ::Date.new(2023, 9, 30)
            )

            # 5 days before end date
            create(
              :soa_secret_scanning_alert_revision,
              date_id: 20230930,
              repository: @repo,
              alert_number: 2,
              alert_created_at: ::Date.new(2023, 9, 30)
            )

            # 4 days before end date
            create(
              :soa_secret_scanning_alert_revision,
              date_id: 20231001,
              repository: @repo,
              alert_number: 3,
              alert_created_at: ::Date.new(2023, 10, 1)
            )

            # Avg is 4.66, should be rounded to 5.
            avg = AgeOfAlerts.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(5, avg.value)

            # Add a 3 day old revision:
            create(
              :soa_secret_scanning_alert_revision,
              date_id: 20231001,
              repository: @repo,
              alert_number: 4,
              alert_created_at: ::Date.new(2023, 10, 2)
            )

            # Avg is 4.25, should be rounded to 4.
            avg = AgeOfAlerts.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(4, avg.value)
            assert_equal(4, avg.alert_count)
          end

          test "filters repos based on the repos_filterer" do
            repo_1 = create(:private_repository, owner: @org).tap do |repo|
              repo_metadata = create(:soa_repository, repository: repo)
              create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_metadata, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
              repo_metadata
            end
            # 5 days old
            create(
              :soa_secret_scanning_alert_revision,
              date_id: 20230930,
              repository: repo_1,
              alert_number: 1,
              alert_created_at: ::Date.new(2023, 9, 30)
            )

            repo_2 = create(:private_repository, owner: @org).tap do |repo|
              repo_metadata = create(:soa_repository, repository: repo)
              create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_metadata, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
              repo_metadata
            end
            # 4 days old
            create(
              :soa_secret_scanning_alert_revision,
              date_id: 20231001,
              repository: repo_2,
              alert_number: 2,
              alert_created_at: ::Date.new(2023, 10, 1)
            )

            repo_3 = create(:private_repository, owner: @org).tap do |repo|
              repo_metadata = create(:soa_repository, repository: repo)
              create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_metadata, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
              repo_metadata
            end
            # 3 days old
            create(
              :soa_secret_scanning_alert_revision,
              date_id: 20231002,
              repository: repo_3,
              alert_number: 3,
              alert_created_at: ::Date.new(2023, 10, 2)
            )

            stub_can_view_all_alerts(false)
            SecurityCenter::AuthorizationEnumerator
              .any_instance
              .expects(:allowed_repository_ids_by_feature_for_organization_member)
              .returns({
                "code_scanning" => [[repo_1.id], false],
                "dependabot_alerts" => [[repo_1.id], false],
                "secret_scanning" => [[repo_1.id], false],
              })

            avg = AgeOfAlerts.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(5, avg.value)
            assert_equal(1, avg.alert_count)
          end

          context "alert-centric filters" do
            test "returns no average age when resolution filters are applied" do
              repo = create(:private_repository, owner: @org).tap do |repo|
                repo_metadata = create(:security_overview_analytics_repository, repository: repo)
                create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_metadata,
                  dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true,
                  secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
                repo_metadata
              end

              # 5 days old
              create(:soa_secret_scanning_alert_revision, date_id: 20230930, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 9, 30))
              # 4 days old
              create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 1))
              # 3 days old
              create(:soa_dependabot_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 2))

              query = QueryParser.new("resolution:risk-accepted")

              stub_can_view_all_alerts(false)
              SecurityCenter::AuthorizationEnumerator
                .any_instance
                .expects(:allowed_repository_ids_by_feature_for_organization_member)
                .returns({
                  "code_scanning" => [[repo.id], false],
                  "dependabot_alerts" => [[repo.id], false],
                  "secret_scanning" => [[repo.id], false],
                })

              avg = AgeOfAlerts.for_organization(
                organization: @org,
                user: @org_admin,
                query:,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
                ).perform

              assert_equal(0, avg.value)
              assert_equal(0, avg.alert_count)
            end

            test "returns average age for alerts with selected severities" do
              repo = create(:private_repository, owner: @org).tap do |repo|
                repo_metadata = create(:security_overview_analytics_repository, repository: repo)
                create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_metadata,
                  dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true,
                  secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
                repo_metadata
              end

              # 5 days old
              create(:soa_secret_scanning_alert_revision, date_id: 20230930, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 9, 30))
              # 4 days old
              create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 1), alert_severity: "critical")
              # 3 days old
              create(:soa_dependabot_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")

              query = QueryParser.new("severity:critical")

              stub_can_view_all_alerts(false)
              SecurityCenter::AuthorizationEnumerator
                .any_instance
                .expects(:allowed_repository_ids_by_feature_for_organization_member)
                .returns({
                  "code_scanning" => [[repo.id], false],
                  "dependabot_alerts" => [[repo.id], false],
                  "secret_scanning" => [[repo.id], false],
                })

              avg = AgeOfAlerts.for_organization(
                organization: @org,
                user: @org_admin,
                query:,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
                ).perform

              assert_equal(5, avg.value)
              assert_equal(2, avg.alert_count)
            end
          end

          context "tool-centric filters" do
            context "dependabot filters" do
              test "returns average age for dependabot alerts with selected ecosystem" do
                repo = create(:private_repository, owner: @org).tap do |repo|
                  repo_metadata = create(:security_overview_analytics_repository, repository: repo)
                  create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_metadata,
                    dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true,
                    secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
                  repo_metadata
                end

                # 5 days old
                create(:soa_dependabot_alert_revision, date_id: 20230930, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 9, 30), ecosystem: "npm")
                # 4 days old
                create(:soa_dependabot_alert_revision, date_id: 20231001, next_revision_date_id: 20231006, repository: repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1), ecosystem: "pip")
                # 3 days old
                create(:soa_dependabot_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2), ecosystem: "npm")

                create(:soa_code_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")

                query = QueryParser.new("dependabot.ecosystem:npm")

                stub_can_view_all_alerts(false)
                SecurityCenter::AuthorizationEnumerator
                  .any_instance
                  .expects(:allowed_repository_ids_by_feature_for_organization_member)
                  .returns({
                    "code_scanning" => [[repo.id], false],
                    "dependabot_alerts" => [[repo.id], false],
                    "secret_scanning" => [[repo.id], false],
                  })

                avg = AgeOfAlerts.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query:,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_equal(4, avg.value)
                assert_equal(2, avg.alert_count)
              end
            end

            context "code scanning filters" do
              test "returns average age for codeql alerts with selected rules" do
                repo = create(:private_repository, owner: @org).tap do |repo|
                  repo_metadata = create(:security_overview_analytics_repository, repository: repo)
                  create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_metadata,
                    dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true,
                    secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
                  repo_metadata
                end

                # 5 days old
                create(:soa_code_scanning_alert_revision, date_id: 20230930, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 9, 30), rule_sarif_identifier: "some-rule")
                # 4 days old
                create(:soa_code_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231006, repository: repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1), rule_sarif_identifier: "other-rule")
                # 3 days old
                create(:soa_code_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2), rule_sarif_identifier: "some-rule")

                create(:soa_dependabot_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")

                query = QueryParser.new("codeql.rule:some-rule")

                stub_can_view_all_alerts(false)
                SecurityCenter::AuthorizationEnumerator
                  .any_instance
                  .expects(:allowed_repository_ids_by_feature_for_organization_member)
                  .returns({
                    "code_scanning" => [[repo.id], false],
                    "dependabot_alerts" => [[repo.id], false],
                    "secret_scanning" => [[repo.id], false],
                  })

                avg = AgeOfAlerts.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query:,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_equal(4, avg.value)
                assert_equal(2, avg.alert_count)
              end
            end

            context "secret scanning filters" do
              test "returns average age for secret scanning alerts with selected token slugs" do
                repo = create(:private_repository, owner: @org).tap do |repo|
                  repo_metadata = create(:security_overview_analytics_repository, repository: repo)
                  create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_metadata,
                    dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true,
                    secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
                  repo_metadata
                end

                # 5 days old
                create(:soa_secret_scanning_alert_revision, date_id: 20230930, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 9, 30), alert_type_slug: "amazon_secret_key")
                # 4 days old
                create(:soa_secret_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231006, repository: repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1), alert_type_slug: "github_token")
                # 3 days old
                create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2), alert_type_slug: "amazon_secret_key")

                create(:soa_dependabot_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")

                query = QueryParser.new("secret-scanning.secret-type:amazon_secret_key")

                stub_can_view_all_alerts(false)
                SecurityCenter::AuthorizationEnumerator
                  .any_instance
                  .expects(:allowed_repository_ids_by_feature_for_organization_member)
                  .returns({
                    "code_scanning" => [[repo.id], false],
                    "dependabot_alerts" => [[repo.id], false],
                    "secret_scanning" => [[repo.id], false],
                  })

                avg = AgeOfAlerts.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query:,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_equal(4, avg.value)
                assert_equal(2, avg.alert_count)
              end

              test "returns average age for secret scanning alerts with selected token providers" do
                repo = create(:private_repository, owner: @org).tap do |repo|
                  repo_metadata = create(:security_overview_analytics_repository, repository: repo)
                  create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_metadata,
                    dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true,
                    secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
                  repo_metadata
                end

                # 5 days old
                create(:soa_secret_scanning_alert_revision, date_id: 20230930, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 9, 30), alert_type_provider: "Amazon AWS")
                # 4 days old
                create(:soa_secret_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231006, repository: repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1), alert_type_provider: "GitHub")
                # 3 days old
                create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2), alert_type_provider: "Amazon AWS")

                create(:soa_dependabot_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")

                query = QueryParser.new("secret-scanning.provider:amazon_aws")

                stub_can_view_all_alerts(false)
                SecurityCenter::AuthorizationEnumerator
                  .any_instance
                  .expects(:allowed_repository_ids_by_feature_for_organization_member)
                  .returns({
                    "code_scanning" => [[repo.id], false],
                    "dependabot_alerts" => [[repo.id], false],
                    "secret_scanning" => [[repo.id], false],
                  })

                avg = AgeOfAlerts.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query:,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_equal(4, avg.value)
                assert_equal(2, avg.alert_count)
              end

              test "returns average age for secret scanning alerts with selected bypassed statuses" do
                repo = create(:private_repository, owner: @org).tap do |repo|
                  repo_metadata = create(:security_overview_analytics_repository, repository: repo)
                  create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_metadata,
                    dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true,
                    secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
                  repo_metadata
                end

                # 5 days old
                create(:soa_secret_scanning_alert_revision, date_id: 20230930, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 9, 30), alert_bypassed: true)
                # 4 days old
                create(:soa_secret_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231006, repository: repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1), alert_bypassed: false)
                # 3 days old
                create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2), alert_bypassed: true)

                create(:soa_dependabot_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")

                query = QueryParser.new("secret-scanning.bypassed:true")

                stub_can_view_all_alerts(false)
                SecurityCenter::AuthorizationEnumerator
                  .any_instance
                  .expects(:allowed_repository_ids_by_feature_for_organization_member)
                  .returns({
                    "code_scanning" => [[repo.id], false],
                    "dependabot_alerts" => [[repo.id], false],
                    "secret_scanning" => [[repo.id], false],
                  })

                avg = AgeOfAlerts.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query:,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_equal(4, avg.value)
                assert_equal(2, avg.alert_count)
              end

              test "returns average age for secret scanning alerts with selected validities" do
                repo = create(:private_repository, owner: @org).tap do |repo|
                  repo_metadata = create(:security_overview_analytics_repository, repository: repo)
                  create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_metadata,
                    dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true,
                    secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
                  repo_metadata
                end

                # Validity query relies on fetching latest revisions to get the current validity value, so create all SS alerts with a latest revision.
                # 5 days old with latest revision
                create(:soa_secret_scanning_alert_revision, date_id: 20230930, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 9, 30), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE)
                create(:soa_secret_scanning_alert_revision, date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 9, 30), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE)
                # 4 days old with latest revision
                create(:soa_secret_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231006, repository: repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_INACTIVE)
                create(:soa_secret_scanning_alert_revision, date_id: 20231006, repository: repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_INACTIVE)
                # 3 days old with latest revision
                create(:soa_secret_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE)
                create(:soa_secret_scanning_alert_revision, date_id: 20231006, repository: repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE)

                create(:soa_dependabot_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")

                query = QueryParser.new("secret-scanning.validity:active")

                stub_can_view_all_alerts(false)
                SecurityCenter::AuthorizationEnumerator
                  .any_instance
                  .expects(:allowed_repository_ids_by_feature_for_organization_member)
                  .returns({
                    "code_scanning" => [[repo.id], false],
                    "dependabot_alerts" => [[repo.id], false],
                    "secret_scanning" => [[repo.id], false],
                  })

                avg = AgeOfAlerts.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query:,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_equal(4, avg.value)
                assert_equal(2, avg.alert_count)
              end
            end
          end

          test "returns correct data when alerts are stored in different slices" do
            updated_at = Time.now
            # Slices are using floor(`updated_at`) to calculate, so adding a second to make sure they are in different slices
            updated_at_2 = updated_at + 1.second

            create(:soa_secret_scanning_alert_revision, date_id: 20230930, repository: @repo, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 02), updated_at: updated_at)
            create(:soa_secret_scanning_alert_revision, date_id: 20230930, repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 9, 30), updated_at: updated_at_2)

            avg = AgeOfAlerts.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(4.0, avg.value)
            assert_equal(2, avg.alert_count)
          end

          private

          def stub_can_view_all_alerts(returns)
            if GitHub.flipper[:security_center_allow_custom_role_view_all_permission_check].enabled? || GitHub.enterprise?
              SecurityProduct::Permissions::OrgAuthz.any_instance.stubs(:can_view_all_alerts?).returns(returns)
            else
              SecurityProduct::Permissions::OrgAuthz.any_instance.stubs(:can_manage_security_products?).returns(returns)
            end
          end
        end
      end
    end
  end
end
