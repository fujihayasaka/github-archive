# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class MeanTimeToRemediateTest < GitHub::TestCase
          VALID_SECURITY_FEATURES = %w[dependabot_alerts secret_scanning codeql]
          QueryParser = ::Search::Queries::SecurityCenter::QueryParser

          fixtures do
            @biz = create(:business)
            @org_admin = create(:user)
            @user_session = create(:user_session, user: @org_admin)
            @org = create(:organization, business: @biz, admin: @org_admin)

            @date = create(:security_overview_analytics_date)
            @repo = create(:private_repository, owner: @org).tap do |repo|
              repo_model = create(:security_overview_analytics_repository, repository: repo)
              create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
            end
          end

          setup do
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_for_resolution?).returns(true)
            ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
              .any_instance.stubs(:selected_backend_security_features)
              .returns(VALID_SECURITY_FEATURES)
          end

          test "returns the mttr when not all features have data" do
            create_repository(repository_id: 12345, organization_id: @org.id)

            # only make secret scanning revisions
            create_alert_revision(repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1)) # 4 days to resolve
            create_alert_revision(repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2)) # 3 days to resolve
            create_alert_revision(repository_id: 12345, date_id: 20231004, alert_number: 3, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3)) # 2 days to resolve

            mttr = MeanTimeToRemediate.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(3, mttr.value)
            assert_equal(3, mttr.alert_count)
          end

          test "returns the mttr when all features have data" do
            create_repository(repository_id: 12345, organization_id: @org.id)
            create_alert_revision(feature: :secret_scanning, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1)) # 3 days to resolve
            create_alert_revision(feature: :code_scanning, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2)) # 2 days to resolve
            create_alert_revision(feature: :dependabot, repository_id: 12345, date_id: 20231004, alert_number: 3, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3)) # 1 days to resolve

            mttr = MeanTimeToRemediate.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(3, mttr.value)
            assert_equal(3, mttr.alert_count)
          end

          test "returns the mttr when all features have data, but one feature is not enabled" do
            repo = create(
              :soa_repository,
              repository_id: 12345,
              organization_id: @org.id,
              name: "repo-12345",
              event_time: Time.now,
            )
            create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo,
              dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: false,
              secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)


            create_alert_revision(feature: :secret_scanning, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1)) # 3 days to resolve
            create_alert_revision(feature: :code_scanning, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2)) # 2 days to resolve
            create_alert_revision(feature: :dependabot, repository_id: 12345, date_id: 20231004, alert_number: 3, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3)) # 1 days to resolve

            mttr = MeanTimeToRemediate.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(2.5, mttr.value)
            assert_equal(2, mttr.alert_count)
          end

          test "returns 0 when no security_features are available" do
            ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
              .any_instance.stubs(:selected_backend_security_features)
              .returns([])

            mttr = MeanTimeToRemediate.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(0, mttr.value)
            assert_equal(0, mttr.alert_count)
          end

          test "uses the most recent alert revision <= period end date" do
            # open alert:
            create_alert_revision(date_id: 20231001, next_revision_date_id: 20231003, alert_resolved: false, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 1))
            # closed alert: this is the revision that should be used. Setting alert_created_at to be different so that we can tell.
            create_alert_revision(date_id: 20231003, next_revision_date_id: 20231006, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 2), alert_resolved_at: ::Date.new(2023, 10, 4)) # 2 days to resolve
            # after period end date, alert is reopened
            create_alert_revision(date_id: 20231006, alert_resolved: false, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 1)) # 5 days to resolve

            mttr = MeanTimeToRemediate.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(3, mttr.value)
            assert_equal(1, mttr.alert_count)
          end

          test "only closed alerts are included in the average" do
            # set alert_resolved_at to make sure it's not included in the mttr
            create_alert_revision(date_id: 20231001, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 1), alert_resolved: false, alert_resolved_at: ::Date.new(2023, 10, 2))
            mttr = MeanTimeToRemediate.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(0, mttr.value)
            assert_equal(0, mttr.alert_count)
          end

          test "alerts that have been reopened and then closed are included in the average, but reopening is ignored" do
            # closed alert:
            create_alert_revision(date_id: 20231002, next_revision_date_id: 20231003, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 1), alert_resolved_at: ::Date.new(2023, 10, 2)) # 2 day to resolve
            # alert reopened
            create_alert_revision(date_id: 20231003, next_revision_date_id: 20231005, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 1), alert_resolved: false)
            # alert closed
            create_alert_revision(date_id: 20231005, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 1), alert_resolved_at: ::Date.new(2023, 10, 5)) # 5 days to resolve

            mttr = MeanTimeToRemediate.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(5, mttr.value)
            assert_equal(1, mttr.alert_count)
          end

          test "alerts resolved before the time period are not included" do
            create_alert_revision(date_id: 20231001, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 1), alert_resolved_at: ::Date.new(2023, 10, 1)) # 0 days to resolve
            mttr = MeanTimeToRemediate.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(0, mttr.value)
            assert_equal(0, mttr.alert_count)
          end

          test "alerts resolved as false positive are not included" do
            create_repository(repository_id: 12345, organization_id: @org.id)
            create_alert_revision(
              feature: :secret_scanning,
              repository_id: 12345,
              date_id: 20231004,
              alert_number: 1,
              alert_resolved_at: ::Date.new(2023, 10, 4),
              alert_created_at: ::Date.new(2023, 10, 1),
              alert_resolution: Base::RESOLUTIONS_SECRET_SCANNING::FALSE_POSITIVE
            ) # 3 days to resolve
            create_alert_revision(
              feature: :code_scanning,
              repository_id: 12345,
              date_id: 20231004,
              alert_number: 2,
              alert_resolved_at: ::Date.new(2023, 10, 4),
              alert_created_at: ::Date.new(2023, 10, 2),
              alert_resolution: Base::RESOLUTIONS_CODE_SCANNING::FALSE_POSITIVE
            ) # 2 days to resolve
            create_alert_revision(
              feature: :dependabot,
              repository_id: 12345,
              date_id: 20231004,
              alert_number: 3,
              alert_resolved_at: ::Date.new(2023, 10, 4),
              alert_created_at: ::Date.new(2023, 10, 3),
              alert_resolution: Base::RESOLUTIONS_DEPENDABOT_ALERTS::INACCURATE
            ) # 1 days to resolve

            mttr = MeanTimeToRemediate.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(0, mttr.value)
            assert_equal(0, mttr.alert_count)
          end

          test "filters repos based on the repo_filterer" do
            repo_metadata = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
            create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_metadata, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
            create_alert_revision(date_id: 20231001, repository_id: 12345, alert_number: 1, alert_created_at: ::Date.new(2023, 10, 1), alert_resolved_at: ::Date.new(2023, 10, 5)) # 5 days to resolve

            repo_metadata = create(:soa_repository, repository_id: 23456, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
            create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_metadata, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
            create_alert_revision(date_id: 20231002, repository_id: 23456, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 2), alert_resolved_at: ::Date.new(2023, 10, 5)) # 4 days to resolve

            repo_metadata = create(:soa_repository, repository_id: 34567, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
            create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_metadata, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
            create_alert_revision(date_id: 20231003, repository_id: 34567, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 3), alert_resolved_at: ::Date.new(2023, 10, 5)) # 3 days to resolve

            if GitHub.flipper[:security_center_allow_custom_role_view_all_permission_check].enabled? || GitHub.enterprise?
              SecurityProduct::Permissions::OrgAuthz.any_instance.stubs(:can_view_all_alerts?).returns(false)
            else
              SecurityProduct::Permissions::OrgAuthz.any_instance.stubs(:can_manage_security_products?).returns(false)
            end
            SecurityCenter::AuthorizationEnumerator
              .any_instance
              .expects(:allowed_repository_ids_by_feature_for_organization_member)
              .returns({
                "code_scanning" => [[12345], false],
                "dependabot_alerts" => [[12345], false],
                "secret_scanning" => [[12345], false],
              })

            mttr = MeanTimeToRemediate.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 1),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(5, mttr.value)
            assert_equal(1, mttr.alert_count)
          end

          context "alert-centric filters" do
            test "alerts resolved as false positive are not included" do
              create_repository(repository_id: 12345, organization_id: @org.id)
              create_alert_revision(
                feature: :secret_scanning,
                repository_id: 12345,
                date_id: 20231004,
                alert_number: 1,
                alert_resolved_at: ::Date.new(2023, 10, 4),
                alert_created_at: ::Date.new(2023, 10, 1),
                alert_resolution: Base::RESOLUTIONS_SECRET_SCANNING::FALSE_POSITIVE
              ) # 3 days to resolve
              create_alert_revision(
                feature: :code_scanning,
                repository_id: 12345,
                date_id: 20231004,
                alert_number: 2,
                alert_resolved_at: ::Date.new(2023, 10, 4),
                alert_created_at: ::Date.new(2023, 10, 2),
                alert_resolution: Base::RESOLUTIONS_CODE_SCANNING::FALSE_POSITIVE
              ) # 2 days to resolve
              create_alert_revision(
                feature: :dependabot,
                repository_id: 12345,
                date_id: 20231004,
                alert_number: 3,
                alert_resolved_at: ::Date.new(2023, 10, 4),
                alert_created_at: ::Date.new(2023, 10, 3),
                alert_resolution: Base::RESOLUTIONS_DEPENDABOT_ALERTS::INACCURATE
              ) # 1 days to resolve

              query = QueryParser.new("resolution:false-positive,risk-accepted")

              mttr = MeanTimeToRemediate.for_organization(
                organization: @org,
                user: @org_admin,
                query:,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              assert_equal(0, mttr.value)
              assert_equal(0, mttr.alert_count)
            end

            test "include alerts resolved from selected severities" do
              create_repository(repository_id: 12345, organization_id: @org.id)
              create_alert_revision(
                feature: :secret_scanning,
                repository_id: 12345,
                date_id: 20231004,
                alert_number: 1,
                alert_resolved_at: ::Date.new(2023, 10, 4),
                alert_created_at: ::Date.new(2023, 10, 1),
                alert_resolution: Base::RESOLUTIONS_SECRET_SCANNING::FALSE_POSITIVE
              ) # 3 days to resolve
              create_alert_revision(
                feature: :code_scanning,
                repository_id: 12345,
                date_id: 20231004,
                alert_number: 2,
                alert_resolved_at: ::Date.new(2023, 10, 4),
                alert_created_at: ::Date.new(2023, 10, 2),
                alert_resolution: Base::RESOLUTIONS_CODE_SCANNING::WONT_FIX,
                alert_severity: "low"
              ) # 2 days to resolve
              create_alert_revision(
                feature: :dependabot,
                repository_id: 12345,
                date_id: 20231004,
                alert_number: 3,
                alert_resolved_at: ::Date.new(2023, 10, 4),
                alert_created_at: ::Date.new(2023, 10, 3),
                alert_resolution: Base::RESOLUTIONS_DEPENDABOT_ALERTS::INACCURATE,
                alert_severity: "high"
              ) # 1 days to resolve

              query = QueryParser.new("severity:low")

              mttr = MeanTimeToRemediate.for_organization(
                organization: @org,
                user: @org_admin,
                query:,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              assert_equal(3, mttr.value)
              assert_equal(1, mttr.alert_count)
            end
          end

          context "tool-centric filters" do
            context "dependabot filters" do
              test "include alerts resolved with selected rule" do
                create_repository(repository_id: 12345, organization_id: @org.id)
                create_alert_revision(
                  feature: :dependabot,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 1,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 1),
                  dependency_scope: "runtime"
                ) # 3 days to resolve
                create_alert_revision(
                  feature: :dependabot,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 2,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 2),
                  dependency_scope: "runtime",
                ) # 2 days to resolve
                create_alert_revision(
                  feature: :dependabot,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 3,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 3),
                  alert_severity: "high",
                  dependency_scope: "development",
                ) # 1 days to resolve
                create_alert_revision(
                  feature: :code_scanning,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 3,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 3),
                  alert_severity: "high"
                ) # 1 days to resolve

                query = QueryParser.new("dependabot.scope:runtime")

                mttr = MeanTimeToRemediate.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query:,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform
                assert_equal(3.5, mttr.value)
                assert_equal(2, mttr.alert_count)
              end
            end

            context "code scanning filters" do
              test "include alerts resolved with selected rule" do
                create_repository(repository_id: 12345, organization_id: @org.id)
                create_alert_revision(
                  feature: :code_scanning,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 1,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 1),
                  rule_sarif_identifier: "rule/some-rule"
                ) # 3 days to resolve
                create_alert_revision(
                  feature: :code_scanning,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 2,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 2),
                  rule_sarif_identifier: "rule/some-rule",
                ) # 2 days to resolve
                create_alert_revision(
                  feature: :code_scanning,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 3,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 3),
                  alert_severity: "high",
                  rule_sarif_identifier: "rule/other-rule",
                ) # 1 days to resolve
                create_alert_revision(
                  feature: :dependabot,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 3,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 3),
                  alert_severity: "high"
                ) # 1 days to resolve

                query = QueryParser.new("codeql.rule:rule/some-rule")

                mttr = MeanTimeToRemediate.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query:,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_equal(3.5, mttr.value)
                assert_equal(2, mttr.alert_count)
              end
            end

            context "secret scanning filters" do
              test "include alerts resolved with selected token slugs" do
                create_repository(repository_id: 12345, organization_id: @org.id)
                create_alert_revision(
                  feature: :secret_scanning,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 1,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 1),
                  alert_type_slug: "amazon_secret_key"
                ) # 3 days to resolve
                create_alert_revision(
                  feature: :secret_scanning,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 2,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 2),
                  alert_type_slug: "amazon_secret_key",
                ) # 2 days to resolve
                create_alert_revision(
                  feature: :secret_scanning,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 3,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 3),
                  alert_severity: "high",
                  alert_type_slug: "github_token",
                ) # 1 days to resolve
                create_alert_revision(
                  feature: :dependabot,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 3,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 3),
                  alert_severity: "high"
                ) # 1 days to resolve

                query = QueryParser.new("secret-scanning.secret-type:amazon_secret_key")

                mttr = MeanTimeToRemediate.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query:,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_equal(3.5, mttr.value)
                assert_equal(2, mttr.alert_count)
              end

              test "include alerts resolved with selected token providers" do
                create_repository(repository_id: 12345, organization_id: @org.id)
                create_alert_revision(
                  feature: :secret_scanning,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 1,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 1),
                  alert_type_provider: "Amazon AWS"
                ) # 3 days to resolve
                create_alert_revision(
                  feature: :secret_scanning,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 2,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 2),
                  alert_type_provider: "Amazon AWS",
                ) # 2 days to resolve
                create_alert_revision(
                  feature: :secret_scanning,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 3,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 3),
                  alert_severity: "high",
                  alert_type_provider: "GitHub",
                ) # 1 days to resolve
                create_alert_revision(
                  feature: :dependabot,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 3,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 3),
                  alert_severity: "high"
                ) # 1 days to resolve

                query = QueryParser.new("secret-scanning.provider:amazon_aws")

                mttr = MeanTimeToRemediate.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query:,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_equal(3.5, mttr.value)
                assert_equal(2, mttr.alert_count)
              end

              test "include alerts resolved with selected validities" do
                create_repository(repository_id: 12345, organization_id: @org.id)
                create_alert_revision(
                  feature: :secret_scanning,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 1,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 1),
                  alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE
                ) # 3 days to resolve
                create_alert_revision(
                  feature: :secret_scanning,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 2,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 2),
                  alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE,
                ) # 2 days to resolve
                create_alert_revision(
                  feature: :secret_scanning,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 3,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 3),
                  alert_severity: "high",
                  alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_INACTIVE,
                ) # 1 days to resolve
                create_alert_revision(
                  feature: :dependabot,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 3,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 3),
                  alert_severity: "high"
                ) # 1 days to resolve

                query = QueryParser.new("secret-scanning.validity:active")

                mttr = MeanTimeToRemediate.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query:,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_equal(3.5, mttr.value)
                assert_equal(2, mttr.alert_count)
              end

              test "include alerts resolved with selected bypassed" do
                create_repository(repository_id: 12345, organization_id: @org.id)
                create_alert_revision(
                  feature: :secret_scanning,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 1,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 1),
                  alert_bypassed: true
                ) # 3 days to resolve
                create_alert_revision(
                  feature: :secret_scanning,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 2,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 2),
                  alert_bypassed: true,
                ) # 2 days to resolve
                create_alert_revision(
                  feature: :secret_scanning,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 3,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 3),
                  alert_severity: "high",
                  alert_bypassed: false,
                ) # 1 days to resolve
                create_alert_revision(
                  feature: :dependabot,
                  repository_id: 12345,
                  date_id: 20231004,
                  alert_number: 3,
                  alert_resolved_at: ::Date.new(2023, 10, 4),
                  alert_created_at: ::Date.new(2023, 10, 3),
                  alert_severity: "high"
                ) # 1 days to resolve

                query = QueryParser.new("secret-scanning.bypassed:true")

                mttr = MeanTimeToRemediate.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query:,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_equal(3.5, mttr.value)
                assert_equal(2, mttr.alert_count)
              end
            end
          end


          test "returns correct data when alerts are stored in different slices" do
            create_repository(repository_id: 12345, organization_id: @org.id)
            updated_at = Time.now
            # Slices are using floor(`updated_at`) to calculate, so adding a second to make sure they are in different slices
            updated_at_2 = updated_at + 1.second
            create_alert_revision(feature: :secret_scanning, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1), updated_at: updated_at) # 3 days to resolve
            # Second alert for secret scanning, which should get returned in separate slice
            create_alert_revision(feature: :secret_scanning, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1), updated_at: updated_at_2) # 3 days to resolve

            create_alert_revision(feature: :code_scanning, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2)) # 2 days to resolve
            create_alert_revision(feature: :dependabot, repository_id: 12345, date_id: 20231004, alert_number: 3, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3)) # 1 days to resolve

            mttr = MeanTimeToRemediate.for_organization(
              organization: @org,
              user: @org_admin,
              query: QueryParser.new,
              start_date: ::Date.new(2023, 10, 2),
              end_date: ::Date.new(2023, 10, 5),
              user_session: @user_session,
              is_open_selected: true,
            ).perform

            assert_equal(3.25, mttr.value)
            assert_equal(4, mttr.alert_count)
          end

          def create_alert_revision(
            date_id:,
            alert_number:,
            alert_created_at:,
            alert_resolved_at: nil,
            feature: :secret_scanning,
            repository_id: @repo.id,
            alert_resolved: true,
            alert_resolution: "wontfix",
            next_revision_date_id: Date::FUTURE_DATE_ID,
            alert_severity: "critical",
            alert_type_slug: "",
            alert_type_provider: "",
            alert_validity: 0,
            alert_bypassed: false,
            rule_sarif_identifier: "",
            ecosystem: "",
            package_name: "",
            dependency_scope: "",
            updated_at: nil
          )
            kwargs = {
              repository_id:,
              alert_number:,
              date_id:,
              next_revision_date_id:,
              alert_resolved:,
              alert_resolution:,
              alert_resolved_at:,
              alert_created_at:,
              updated_at:,
            }

            if feature == :secret_scanning
              kwargs = kwargs.merge({
                alert_type_slug:,
                alert_type_provider:,
                alert_validity:,
                alert_bypassed:
              })
            elsif feature == :code_scanning
              kwargs = kwargs.merge({
                rule_sarif_identifier:,
                alert_severity:
              })
            elsif feature == :dependabot
              kwargs = kwargs.merge({
                ecosystem:,
                package_name:,
                dependency_scope:,
                alert_severity:
              })
            end

            create(
              "soa_#{feature}_alert_revision".to_sym,
              **kwargs
            )
          end

          def create_repository(
            repository_id:,
            organization_id: @org.id,
            archived: false,
            visibility: "private"
          )
            repo = create(
              :soa_repository,
              repository_id:,
              organization_id:,
              name: "repo-#{repository_id}",
              archived:,
              event_time: Time.now,
              visibility:
            )
            create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
            repo
          end
        end
      end
    end
  end
end
