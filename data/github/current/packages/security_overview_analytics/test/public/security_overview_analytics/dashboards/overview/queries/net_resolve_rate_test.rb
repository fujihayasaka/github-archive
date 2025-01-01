# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class NetResolveRateTest < GitHub::TestCase
          VALID_SECURITY_FEATURES = %w[dependabot_alerts secret_scanning codeql]
          QueryParser = ::Search::Queries::SecurityCenter::QueryParser

          fixtures do
            @biz = create(:business)
            @org_admin = create(:user)
            @user_session = create(:user_session, user: @org_admin)
            @org = create(:organization, business: @biz, admin: @org_admin)
          end

          setup do
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_class?).returns(true)
            ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
              .any_instance.stubs(:selected_backend_security_features)
              .returns(VALID_SECURITY_FEATURES)
          end

          context "#perform" do
            test "returns the net resolve rate when not all features have data" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # Numerator (alerts resolved)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3))

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_resolved_at: nil, alert_created_at: ::Date.new(2023, 10, 2))

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              ).perform
              assert_equal 300, net_resolve_rate.value
            end

            test "returns the net resolve rate when some features are disabled" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model,
                dependabot_alerts_enabled: true,
                code_scanning_enabled: true,
                secret_scanning_enabled: false,
                secret_scanning_push_protection_enabled: true,
                advanced_security_enabled: true)

              # Numerator (alerts resolved)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 7, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 8, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 9, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3))

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              ).perform
              assert_equal 150, net_resolve_rate.value
            end

            test "returns the net resolve rate when some features are not provided" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model,
                dependabot_alerts_enabled: true,
                code_scanning_enabled: true,
                secret_scanning_enabled: true,
                secret_scanning_push_protection_enabled: true,
                advanced_security_enabled: true)

              # Numerator (alerts resolved)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 7, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 8, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 9, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3))

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))

              ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                .any_instance.stubs(:selected_backend_security_features)
                .returns([SecurityFeaturesParser::TOOL_CODEQL, ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS])

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              ).perform
              assert_equal 150, net_resolve_rate.value
            end

            test "returns zero for the net resolve rate when all features are disabled" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model,
                dependabot_alerts_enabled: false,
                code_scanning_enabled: false,
                secret_scanning_enabled: false,
                secret_scanning_push_protection_enabled: true,
                advanced_security_enabled: true)

              # Numerator (alerts resolved)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3))

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              ).perform
              assert_equal 0, net_resolve_rate.value
            end

            test "returns zero for the net resolve rate when no security features are provided" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model,
                dependabot_alerts_enabled: true,
                code_scanning_enabled: true,
                secret_scanning_enabled: true,
                secret_scanning_push_protection_enabled: true,
                advanced_security_enabled: true)

              # Numerator (alerts resolved)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3))

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))

              ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                    .any_instance.stubs(:selected_backend_security_features)
                    .returns([])

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              ).perform
              assert_equal 0, net_resolve_rate.value
            end

            test "returns the net resolve rate when all features have data" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # Numerator (alerts resolved)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3))

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 5))

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              ).perform
              assert_equal 100, net_resolve_rate.value
            end

            test "alerts that entered the period closed are included" do
              # Calculating closed alerts list is expensive with current data shape, and outside of scope for MVP
              # ref https://github.com/github/security-center/issues/3845

              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # Numerator (alerts resolved)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))

              # alerts closed before the period, reopened and closed during the period
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20230930, next_revision_date_id: 20231001, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 9, 30), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 4))

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              ).perform
              assert_equal 300, net_resolve_rate.value
            end

            test "alerts that are closed during the time period but open at the end of it are not included" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # Numerator (alerts resolved)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))

              # alerts closed during time period and reopened before the end
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231002, next_revision_date_id: 20231003, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 2), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 1))

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 4))

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              ).perform
              assert_equal 100, net_resolve_rate.value
            end

            test "alerts resolved before the time period are not included" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # alert closed before time period
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 10, 1))

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 4))

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              ).perform
              assert_equal 0, net_resolve_rate.value
            end

            test "when no opened alerts (denominator 0), set denominator to 1" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # alert closed
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231002, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 2), alert_created_at: ::Date.new(2023, 10, 2))

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              ).perform
              assert_equal 100, net_resolve_rate.value
            end

            test "rounds the percentage to the nearest whole percent" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # Numerator (alerts resolved)
              5.times do |i|
                create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: i, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              end

              # Denominator (alerts opened)
              3.times do |i|
                create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: i + 5, alert_resolved: false, alert_resolved_at: nil, alert_created_at: ::Date.new(2023, 10, 2))
              end

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              ).perform

              # 5/3 = 1.666... --> 167%
              assert_equal 167, net_resolve_rate.value
            end

            test "filters repos based on the repos_filterer" do
              # Numerator (alerts resolved)
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              repo_model = create(:soa_repository, repository_id: 23456, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:soa_secret_scanning_alert_revision, repository_id: 23456, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              repo_model = create(:soa_repository, repository_id: 34567, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 4, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))

              SecurityProduct::Permissions::OrgAuthz.any_instance.stubs(:can_manage_security_products?).returns(false)
              SecurityCenter::AuthorizationEnumerator
                .any_instance
                .expects(:allowed_repository_ids_by_feature_for_organization_member)
                .returns({
                  "code_scanning" => [[12345], false],
                  "dependabot_alerts" => [[12345], false],
                  "secret_scanning" => [[12345], false],
                })

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 1),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              ).perform
              assert_equal 100, net_resolve_rate.value
            end

            context "alert-centric filters" do
              test "returns NRR that includes alerts with selected resolutions" do
                repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                # Numerator (alerts resolved)
                create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: Base::RESOLUTIONS_SECRET_SCANNING::WONT_FIX)
                create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_resolution: Base::RESOLUTIONS_CODE_SCANNING::WONT_FIX)
                create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3), alert_resolution: Base::RESOLUTIONS_DEPENDABOT_ALERTS::INACCURATE)

                # Denominator (alerts opened)
                create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
                create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
                create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 5))

                query = QueryParser.new("resolution:risk-accepted")
                net_resolve_rate = NetResolveRate.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query:,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  return_alert_count: false,
                  is_open_selected: true,
                ).perform
                assert_equal 67, net_resolve_rate.value
              end

              test "returns NRR for alerts with selected severities" do
                repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                # Numerator (alerts resolved)
                create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
                create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "high")
                create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3), alert_severity: "high")
                # Denominator (alerts opened)
                create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
                create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")
                create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 5), alert_severity: "high")

                query = QueryParser.new("severity:high")
                net_resolve_rate = NetResolveRate.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query:,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  return_alert_count: false,
                  is_open_selected: true,
                ).perform
                assert_equal 200, net_resolve_rate.value
              end
            end

            context "tool-centric filters" do
              context "dependabot filters" do
                test "returns NRR for alerts with selected ecosystem" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Numerator (alerts resolved)
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1), ecosystem: "npm")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "high")
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3), ecosystem: "npm")
                  # Denominator (alerts opened)
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), ecosystem: "npm")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 5), ecosystem: "pip")

                  query = QueryParser.new("dependabot.ecosystem:npm")
                  net_resolve_rate = NetResolveRate.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query:,
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    return_alert_count: false,
                    is_open_selected: true,
                  ).perform
                  assert_equal 200, net_resolve_rate.value
                end
              end

              context "code scanning filters" do
                test "returns NRR for alerts with selected token slugs" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Numerator (alerts resolved)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1), tool: "CodeQL", rule_sarif_identifier: "rule/some-rule")
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "high")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3), tool: "other-tool", rule_sarif_identifier: "rule/some-rule")
                  # Denominator (alerts opened)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), tool: "CodeQL", rule_sarif_identifier: "rule/some-rule")
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 5), tool: "other-tool", rule_sarif_identifier: "other-rule")

                  query = QueryParser.new("codeql.rule:rule/some-rule")
                  net_resolve_rate = NetResolveRate.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query:,
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    return_alert_count: false,
                    is_open_selected: true,
                  ).perform

                  assert_equal 100, net_resolve_rate.value
                end
              end

              context "secret scanning filters" do
                test "returns NRR for alerts with selected token slugs" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Numerator (alerts resolved)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1), alert_type_slug: "amazon_aws")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "high")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3), alert_type_slug: "amazon_aws")
                  # Denominator (alerts opened)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_type_slug: "amazon_aws")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 5), alert_type_slug: "github_token")

                  query = QueryParser.new("secret-scanning.secret-type:amazon_aws")
                  net_resolve_rate = NetResolveRate.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query:,
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    return_alert_count: false,
                    is_open_selected: true,
                  ).perform
                  assert_equal 200, net_resolve_rate.value
                end

                test "returns NRR for alerts with selected token providers" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Numerator (alerts resolved)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1), alert_type_provider: "Amazon AWS")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "high")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3), alert_type_provider: "Amazon AWS")
                  # Denominator (alerts opened)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_type_provider: "Amazon AWS")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 5), alert_type_provider: "GitHub")

                  query = QueryParser.new("secret-scanning.provider:amazon_aws")
                  net_resolve_rate = NetResolveRate.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query:,
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    return_alert_count: false,
                    is_open_selected: true,
                  ).perform
                  assert_equal 200, net_resolve_rate.value
                end

                test "returns NRR for alerts with selected validities" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Numerator (alerts resolved)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "high")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE)
                  # Denominator (alerts opened)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 5), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_INACTIVE)

                  query = QueryParser.new("secret-scanning.validity:active")
                  net_resolve_rate = NetResolveRate.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query:,
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    return_alert_count: false,
                    is_open_selected: true,
                  ).perform
                  assert_equal 200, net_resolve_rate.value
                end

                test "returns NRR for alerts with selected bypassed status" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Numerator (alerts resolved)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1), alert_bypassed: true)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "high")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3), alert_bypassed: true)
                  # Denominator (alerts opened)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_bypassed: true)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 5), alert_bypassed: false)

                  query = QueryParser.new("secret-scanning.bypassed:true")
                  net_resolve_rate = NetResolveRate.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query:,
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    return_alert_count: false,
                    is_open_selected: true,
                  ).perform
                  assert_equal 200, net_resolve_rate.value
                end
              end
            end
          end

          context "#perform with return_alert_count" do
            test "returns the net resolve data when not all features have data" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # Numerator (alerts resolved)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3))

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_resolved_at: nil, alert_created_at: ::Date.new(2023, 10, 2))

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: true,
                is_open_selected: true,
              ).perform
              assert_nil net_resolve_rate.value
              assert_equal 1, net_resolve_rate.open_count
              assert_equal 3, net_resolve_rate.closed_count
            end

            test "returns the net resolve data when some features are disabled" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model,
                dependabot_alerts_enabled: true,
                code_scanning_enabled: true,
                secret_scanning_enabled: false,
                secret_scanning_push_protection_enabled: true,
                advanced_security_enabled: true)

              # Numerator (alerts resolved)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 7, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 8, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 9, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3))

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: true,
                is_open_selected: true,
              ).perform

              assert_nil net_resolve_rate.value
              assert_equal 2, net_resolve_rate.open_count
              assert_equal 3, net_resolve_rate.closed_count
            end

            test "returns the net resolve data when some features are not provided" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model,
                dependabot_alerts_enabled: true,
                code_scanning_enabled: true,
                secret_scanning_enabled: true,
                secret_scanning_push_protection_enabled: true,
                advanced_security_enabled: true)

              # Numerator (alerts resolved)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 7, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 8, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 9, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3))

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))

              ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                .any_instance.stubs(:selected_backend_security_features)
                .returns([SecurityFeaturesParser::TOOL_CODEQL, ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS])

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: true,
                is_open_selected: true,
              ).perform

              assert_nil net_resolve_rate.value
              assert_equal 2, net_resolve_rate.open_count
              assert_equal 3, net_resolve_rate.closed_count
            end

            test "returns zero for the net resolve data when all features are disabled" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model,
                dependabot_alerts_enabled: false,
                code_scanning_enabled: false,
                secret_scanning_enabled: false,
                secret_scanning_push_protection_enabled: true,
                advanced_security_enabled: true)

              # Numerator (alerts resolved)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3))

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: true,
                is_open_selected: true,
              ).perform

              assert_nil net_resolve_rate.value
              assert_equal 0, net_resolve_rate.open_count
              assert_equal 0, net_resolve_rate.closed_count
            end

            test "returns zero for the net resolve data when no security features are provided" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model,
                dependabot_alerts_enabled: true,
                code_scanning_enabled: true,
                secret_scanning_enabled: true,
                secret_scanning_push_protection_enabled: true,
                advanced_security_enabled: true)

              # Numerator (alerts resolved)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3))

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))

              ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                .any_instance.stubs(:selected_backend_security_features)
                .returns([])

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: true,
                is_open_selected: true,
              ).perform

              assert_nil net_resolve_rate.value
              assert_equal 0, net_resolve_rate.open_count
              assert_equal 0, net_resolve_rate.closed_count
            end

            test "returns the net resolve data when all features have data" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # Numerator (alerts resolved)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3))

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
              create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 5))

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: true,
                is_open_selected: true,
              ).perform

              assert_nil net_resolve_rate.value
              assert_equal 3, net_resolve_rate.open_count
              assert_equal 3, net_resolve_rate.closed_count
            end

            test "alerts that entered the period closed are included" do
              # Calculating closed alerts list is expensive with current data shape, and outside of scope for MVP
              # ref https://github.com/github/security-center/issues/3845

              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # Numerator (alerts resolved)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2))

              # alerts closed before the period, reopened and closed during the period
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20230930, next_revision_date_id: 20231001, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 9, 30), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, next_revision_date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 3), alert_created_at: ::Date.new(2023, 10, 1))

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 4))

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: true,
                is_open_selected: true,
              ).perform

              assert_nil net_resolve_rate.value
              assert_equal 1, net_resolve_rate.open_count
              assert_equal 3, net_resolve_rate.closed_count
            end

            test "alerts that are closed during the time period but open at the end of it are not included" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # Numerator (alerts resolved)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))

              # alerts closed during time period and reopened before the end
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231002, next_revision_date_id: 20231003, alert_number: 3, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 2), alert_created_at: ::Date.new(2023, 10, 1))
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 1))

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 4))

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: true,
                is_open_selected: true,
              ).perform

              assert_nil net_resolve_rate.value
              assert_equal 1, net_resolve_rate.open_count
              assert_equal 1, net_resolve_rate.closed_count
            end

            test "alerts resolved before the time period are not included" do
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # alert closed before time period
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231001, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 1), alert_created_at: ::Date.new(2023, 10, 1))

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 4))

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: true,
                is_open_selected: true,
              ).perform

              assert_nil net_resolve_rate.value
              assert_equal 1, net_resolve_rate.open_count
              assert_equal 0, net_resolve_rate.closed_count
            end

            test "filters repos based on the repos_filterer" do
              # Numerator (alerts resolved)
              repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              repo_model = create(:soa_repository, repository_id: 23456, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:soa_secret_scanning_alert_revision, repository_id: 23456, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
              create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              repo_model = create(:soa_repository, repository_id: 34567, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
              create(:security_overview_analytics_feature_status_revision, date_id: 20231004, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

              # Denominator (alerts opened)
              create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 4, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))

              SecurityProduct::Permissions::OrgAuthz.any_instance.stubs(:can_manage_security_products?).returns(false)
              SecurityCenter::AuthorizationEnumerator
                .any_instance
                .expects(:allowed_repository_ids_by_feature_for_organization_member)
                .returns({
                  "code_scanning" => [[12345], false],
                  "dependabot_alerts" => [[12345], false],
                  "secret_scanning" => [[12345], false],
                })

              net_resolve_rate = NetResolveRate.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: true,
                is_open_selected: true,
              ).perform

              assert_nil net_resolve_rate.value
              assert_equal 1, net_resolve_rate.open_count
              assert_equal 1, net_resolve_rate.closed_count
            end

            context "alert-centric filters" do
              test "returns NRR that includes alerts with selected resolutions" do
                repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                # Numerator (alerts resolved)
                create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1), alert_resolution: Base::RESOLUTIONS_SECRET_SCANNING::WONT_FIX)
                create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_resolution: Base::RESOLUTIONS_CODE_SCANNING::WONT_FIX)
                create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3), alert_resolution: Base::RESOLUTIONS_DEPENDABOT_ALERTS::INACCURATE)

                # Denominator (alerts opened)
                create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
                create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
                create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 5))

                query = QueryParser.new("resolution:risk-accepted")
                net_resolve_rate = NetResolveRate.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query:,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  return_alert_count: true,
                  is_open_selected: true,
                ).perform

                assert_nil net_resolve_rate.value
                assert_equal 3, net_resolve_rate.open_count
                assert_equal 2, net_resolve_rate.closed_count
              end

              test "returns NRR for alerts with selected severities" do
                repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                # Numerator (alerts resolved)
                create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1))
                create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "high")
                create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3), alert_severity: "high")
                # Denominator (alerts opened)
                create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2))
                create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")
                create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 5), alert_severity: "high")

                query = QueryParser.new("severity:high")
                net_resolve_rate = NetResolveRate.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query:,
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  return_alert_count: true,
                  is_open_selected: true,
                ).perform

                assert_nil net_resolve_rate.value
                assert_equal 1, net_resolve_rate.open_count
                assert_equal 2, net_resolve_rate.closed_count
              end
            end

            context "tool-centric filters" do
              context "dependabot filters" do
                test "returns NRR for alerts with selected ecosystem" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Numerator (alerts resolved)
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1), ecosystem: "npm")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "high")
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3), ecosystem: "npm")
                  # Denominator (alerts opened)
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), ecosystem: "npm")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 5), ecosystem: "pip")

                  query = QueryParser.new("dependabot.ecosystem:npm")
                  net_resolve_rate = NetResolveRate.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query:,
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    return_alert_count: true,
                    is_open_selected: true,
                  ).perform

                  assert_nil net_resolve_rate.value
                  assert_equal 1, net_resolve_rate.open_count
                  assert_equal 2, net_resolve_rate.closed_count
                end
              end

              context "code scanning filters" do
                test "returns NRR for alerts with selected token slugs" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Numerator (alerts resolved)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1), tool: "CodeQL", rule_sarif_identifier: "rule/some-rule")
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "high")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3), tool: "other-tool", rule_sarif_identifier: "rule/some-rule")
                  # Denominator (alerts opened)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), tool: "CodeQL", rule_sarif_identifier: "rule/some-rule")
                  create(:soa_dependabot_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 5), tool: "other-tool", rule_sarif_identifier: "other-rule")

                  query = QueryParser.new("codeql.rule:rule/some-rule")
                  net_resolve_rate = NetResolveRate.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query:,
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    return_alert_count: true,
                    is_open_selected: true,
                  ).perform

                  assert_nil net_resolve_rate.value
                  assert_equal 1, net_resolve_rate.open_count
                  assert_equal 1, net_resolve_rate.closed_count
                end
              end

              context "secret scanning filters" do
                test "returns NRR for alerts with selected token slugs" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Numerator (alerts resolved)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1), alert_type_slug: "amazon_aws")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "high")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3), alert_type_slug: "amazon_aws")
                  # Denominator (alerts opened)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_type_slug: "amazon_aws")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 5), alert_type_slug: "github_token")

                  query = QueryParser.new("secret-scanning.secret-type:amazon_aws")
                  net_resolve_rate = NetResolveRate.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query:,
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    return_alert_count: true,
                    is_open_selected: true,
                  ).perform

                  assert_nil net_resolve_rate.value
                  assert_equal 1, net_resolve_rate.open_count
                  assert_equal 2, net_resolve_rate.closed_count
                end

                test "returns NRR for alerts with selected token providers" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Numerator (alerts resolved)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1), alert_type_provider: "Amazon AWS")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "high")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3), alert_type_provider: "Amazon AWS")
                  # Denominator (alerts opened)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_type_provider: "Amazon AWS")
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 5), alert_type_provider: "GitHub")

                  query = QueryParser.new("secret-scanning.provider:amazon_aws")
                  net_resolve_rate = NetResolveRate.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query:,
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    return_alert_count: true,
                    is_open_selected: true,
                  ).perform

                  assert_nil net_resolve_rate.value
                  assert_equal 1, net_resolve_rate.open_count
                  assert_equal 2, net_resolve_rate.closed_count
                end

                test "returns NRR for alerts with selected validities" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Numerator (alerts resolved)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "high")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE)
                  # Denominator (alerts opened)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 5), alert_validity: SecretScanningAlertRevision::SecretScanningTokenValidity::TOKEN_VALIDITY_INACTIVE)

                  query = QueryParser.new("secret-scanning.validity:active")
                  net_resolve_rate = NetResolveRate.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query:,
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    return_alert_count: true,
                    is_open_selected: true,
                  ).perform

                  assert_nil net_resolve_rate.value
                  assert_equal 1, net_resolve_rate.open_count
                  assert_equal 2, net_resolve_rate.closed_count
                end

                test "returns NRR for alerts with selected bypassed status" do
                  repo_model = create(:soa_repository, repository_id: 12345, organization_id: @org.id, archived: false, event_time: Time.now, visibility: "private")
                  create(:security_overview_analytics_feature_status_revision, repository_metadata: repo_model, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                  # Numerator (alerts resolved)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 1, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 1), alert_bypassed: true)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 2, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "high")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231004, alert_number: 4, alert_resolved: true, alert_resolved_at: ::Date.new(2023, 10, 4), alert_created_at: ::Date.new(2023, 10, 3), alert_bypassed: true)
                  # Denominator (alerts opened)
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 3, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_bypassed: true)
                  create(:soa_code_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 5, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 2), alert_severity: "low")
                  create(:soa_secret_scanning_alert_revision, repository_id: 12345, date_id: 20231003, alert_number: 6, alert_resolved: false, alert_created_at: ::Date.new(2023, 10, 5), alert_bypassed: false)

                  query = QueryParser.new("secret-scanning.bypassed:true")
                  net_resolve_rate = NetResolveRate.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query:,
                    start_date: ::Date.new(2023, 10, 2),
                    end_date: ::Date.new(2023, 10, 5),
                    user_session: @user_session,
                    return_alert_count: true,
                    is_open_selected: true,
                  ).perform

                  assert_nil net_resolve_rate.value
                  assert_equal 1, net_resolve_rate.open_count
                  assert_equal 2, net_resolve_rate.closed_count
                end
              end
            end
          end

        end
      end
    end
  end
end
