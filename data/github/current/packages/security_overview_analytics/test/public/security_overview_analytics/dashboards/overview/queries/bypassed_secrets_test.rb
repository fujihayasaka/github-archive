# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class BypassedSecretsTest < GitHub::TestCase
          QueryParser = ::Search::Queries::SecurityCenter::QueryParser

          fixtures do
            @biz = create(:business)
            @org_admin = create(:user)
            @user_session = create(:user_session, user: @org_admin)
            @org = create(:organization, business: @biz, admin: @org_admin)
            @repo_1 = create(:private_repository, owner: @org).tap do |repo|
              create(:security_overview_analytics_repository, repository: repo)
            end
            @repo_2 = create(:private_repository, owner: @org).tap do |repo|
              create(:security_overview_analytics_repository, repository: repo)
            end
          end

          setup do
            @alerts_filterer = AlertsFilterer.new(query: QueryParser.new, scope: @org, user: @org_admin)
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_for_resolution?).returns(true)
            ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
              .any_instance.stubs(:selected_backend_security_features)
              .returns(%w[dependabot_alerts secret_scanning codeql])
          end

          context "#perform" do
            test "it returns the value properly from request" do
              ::SecretScanning::Services::MetricsService
                .stubs(:get_push_protection_metrics_for_repos)
                .returns(
                  [
                    SecretScanning::Models::PushProtectionMetricsForRepos.new(
                      bypassed_alert_count: 1,
                      successful_block_count: 2,
                      total_block_count: 3
                    ),
                    false
                  ]
                )

              res, err = BypassedSecrets.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.current,
                end_date: ::Date.current,
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              assert_equal({
                bypassed_alerts_count: 1,
                successful_blocks_count: 2,
                total_blocks_count: 3
              }, res)
              refute err
            end

            test "does not call auth enumerator if user can manage security products" do
              if GitHub.flipper[:security_center_allow_custom_role_view_all_permission_check].enabled?
                SecurityProduct::Permissions::OrgAuthz.any_instance.stubs(:can_view_all_alerts?).returns(true)
              else
                SecurityProduct::Permissions::OrgAuthz.any_instance.stubs(:can_manage_security_products?).returns(true)
              end
              SecurityCenter::AuthorizationEnumerator.any_instance.expects(:allowed_repository_ids_by_feature_for_organization_member).never

              ::SecretScanning::Services::MetricsService
                .stubs(:get_push_protection_metrics_for_repos)
                .returns(
                  [
                    SecretScanning::Models::PushProtectionMetricsForRepos.new(
                      bypassed_alert_count: 1,
                      successful_block_count: 2,
                      total_block_count: 3
                    ),
                    false
                  ]
                )

              res, err = BypassedSecrets.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.current,
                end_date: ::Date.current,
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              assert_equal({
                bypassed_alerts_count: 1,
                successful_blocks_count: 2,
                total_blocks_count: 3
              }, res)
              refute err
            end

            test "calls auth enumerator if user cannot manage security products" do
              if GitHub.flipper[:security_center_allow_custom_role_view_all_permission_check].enabled? || GitHub.enterprise?
                SecurityProduct::Permissions::OrgAuthz.any_instance.stubs(:can_view_all_alerts?).returns(false)
              else
                SecurityProduct::Permissions::OrgAuthz.any_instance.stubs(:can_manage_security_products?).returns(false)
              end
              SecurityCenter::AuthorizationEnumerator.any_instance
                .expects(:allowed_repository_ids_by_feature_for_organization_member)
                .returns({
                  "code_scanning" => [@org.repositories.map(&:id), false],
                  "dependabot_alerts" => [@org.repositories.map(&:id), false],
                  "secret_scanning" => [@org.repositories.map(&:id), false],
                })
                .once


              ::SecretScanning::Services::MetricsService
              .stubs(:get_push_protection_metrics_for_repos)
              .returns(
                [
                  SecretScanning::Models::PushProtectionMetricsForRepos.new(
                    bypassed_alert_count: 1,
                    successful_block_count: 2,
                    total_block_count: 3
                  ),
                  false
                ]
              )

              res, err = BypassedSecrets.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.current,
                end_date: ::Date.current,
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              assert_equal({
                bypassed_alerts_count: 1,
                successful_blocks_count: 2,
                total_blocks_count: 3
              }, res)
              refute err
            end

            context "when secret scanning is not visible" do
              test "it returns an empty response" do
                ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                  .any_instance.stubs(:selected_backend_security_features)
                  .returns([])

                res, err = BypassedSecrets.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: ::Date.current,
                  end_date: ::Date.current,
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_equal({
                  no_data: "No repositories found"
                }, res)
                refute(err)
              end
            end

            context "when an error occurs in TSS" do
              test "it returns an empty response and true for the error" do
                GitHub::Proto::SecretScanning::Api::V1::MetricsAPI
                  .any_instance
                  .stubs(:get_push_protection_metrics_for_repos)
                  .raises(Faraday::ConnectionFailed.new(""))

                res, err = BypassedSecrets.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: ::Date.current,
                  end_date: ::Date.current,
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_equal({
                  bypassed_alerts_count: 0,
                  successful_blocks_count: 0,
                  total_blocks_count: 0
                }, res)
                assert(err)
              end
            end

            context "when alert-centric filters are applied" do
              test "returns no data if the queried severity is not 'critical'" do
                res, err = BypassedSecrets.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new("severity:high"),
                  start_date: ::Date.current,
                  end_date: ::Date.current,
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_equal({
                  no_data: "No repositories found"
                }, res)
                refute(err)
              end

              test "calls TSS only when severity filter applied is 'critical'" do
                query_parser = QueryParser.new("severity:critical")
                ::SecretScanning::Services::MetricsService
                .stubs(:get_push_protection_metrics_for_repos)
                .returns(
                  [
                    SecretScanning::Models::PushProtectionMetricsForRepos.new(
                      bypassed_alert_count: 1,
                      successful_block_count: 2,
                      total_block_count: 3
                    ),
                    false
                  ]
                )

                res, err = BypassedSecrets.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: query_parser,
                  start_date: ::Date.current,
                  end_date: ::Date.current,
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_equal({
                  bypassed_alerts_count: 1,
                  successful_blocks_count: 2,
                  total_blocks_count: 3
                }, res)
                refute(err)
              end

              context "tool-centric filters" do
                test "returns no data if other tool filters are applied" do
                  query_parser = QueryParser.new("codeql.rule:some-rule")

                  new_org = create(:organization, business: @biz)
                  new_repo = create(:private_repository, owner: new_org).tap do |repo|
                    create(:security_overview_analytics_repository, repository: repo)
                  end
                  create(:soa_secret_scanning_alert_revision, date_id: 20231005, repository: new_repo, alert_number: 1, alert_created_at: DateTime.parse("2023-10-05 08:00:00"), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE)

                  new_repo_filterer = OrgReposFilterer.new(
                    organization: new_org,
                    query: ::Search::Queries::SecurityCenter::QueryParser.new(""),
                    user: new_org.admin,
                    user_session: @user_session
                  )

                  SecretScanning::Services::MetricsService
                    .expects(:get_push_protection_metrics_for_repos)
                    .never

                  res, err = BypassedSecrets.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: query_parser,
                    start_date: ::Date.current,
                    end_date: ::Date.current,
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform
                end
              end
            end
          end
        end
      end
    end
  end
end
