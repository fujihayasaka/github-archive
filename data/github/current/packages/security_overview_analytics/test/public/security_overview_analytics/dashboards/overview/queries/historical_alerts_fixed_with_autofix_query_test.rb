# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class HistoricalAlertsFixedWithAutofixQueryTest < GitHub::TestCase
          QueryParser = ::Search::Queries::SecurityCenter::QueryParser

          fixtures do
            date_id = 20240801
            date = Date.find_by(id: date_id) || create(:soa_date, date_value: ::Date.parse(date_id.to_s))

            @biz = create(:business)
            @org_admin = create(:user)
            @user_session = create(:user_session, user: @org_admin)
            @org = create(:organization, business: @biz, admin: @org_admin)
            soa_date = create(:security_overview_analytics_date)
            @repo = create(:private_repository, owner: @org).tap do |repo|
              repo_metadata = create(:security_overview_analytics_repository, repository: repo)
              create(:security_overview_analytics_feature_status_revision, date: soa_date, repository_metadata: repo_metadata, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
              repo_metadata
            end

            [
              create(:private_repository, owner: @org),
              create(:public_repository, owner: @org),
            ].each do |repository|
              repository_metadata = create(:soa_repository, repository:)
              create(:soa_feature_status_revision, repository_metadata:, date:, code_scanning_enabled: true)

              [
                { has_autofix: false, autofix_accepted: false, alert_resolved: false },
                { has_autofix: false, autofix_accepted: false, alert_resolved: true, alert_resolution: nil },
                { has_autofix: false, autofix_accepted: false, alert_resolved: true, alert_resolution: 2 },
                # has_autofix: false, autofix_accepted: true is not a valid combination
                { has_autofix: true, autofix_accepted: false, alert_resolved: false },
                { has_autofix: true, autofix_accepted: false, alert_resolved: true, alert_resolution: nil },
                { has_autofix: true, autofix_accepted: false, alert_resolved: true, alert_resolution: 2 },
                { has_autofix: true, autofix_accepted: true, alert_resolved: false },
                { has_autofix: true, autofix_accepted: true, alert_resolved: true, alert_resolution: nil },
                { has_autofix: true, autofix_accepted: true, alert_resolved: true, alert_resolution: 2 },
              ].each_with_index do |scenario, idx|
                create(
                  :soa_code_scanning_alert_revision,
                  repository_metadata:,
                  alert_number: idx,
                  date_id:,
                  **scenario,
                )
              end
            end
          end

          setup do
            Timecop.freeze do
              @default_end_date = ::Date.parse("2024-08-14")
              @default_start_date = @default_end_date - 30.days
            end

            if GitHub.enterprise?
              SecurityCenter::SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(true)
            end
          end

          context "for_organization" do
            context "#perform" do
              test "it returns the correct response" do
                sut = HistoricalAlertsFixedWithAutofixQuery.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                  user_session: @user_session,
                  is_open_selected: true,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 2, actual.accepted
                assert_equal 12, actual.suggested
              end

              test "it filters to accessible repositories" do
                sut = HistoricalAlertsFixedWithAutofixQuery.for_organization(
                  organization: @org,
                  user: @org_admin,
                  user_session: @user_session,
                  query: QueryParser.new,
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                  is_open_selected: true,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 2, actual.accepted
                assert_equal 12, actual.suggested
              end

              test "it applies repo filters" do
                sut = HistoricalAlertsFixedWithAutofixQuery.for_organization(
                  organization: @org,
                  user: @org_admin,
                  user_session: @user_session,
                  query: QueryParser.new("visibility:private"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                  is_open_selected: true,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 1, actual.accepted
                assert_equal 6, actual.suggested
              end

              test "it applies alert filters" do
                sut = HistoricalAlertsFixedWithAutofixQuery.for_organization(
                  organization: @org,
                  user: @org_admin,
                  user_session: @user_session,
                  query: QueryParser.new("severity:critical"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                  is_open_selected: true,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 2, actual.accepted
                assert_equal 12, actual.suggested
              end

              test "it returns zero counts if code scanning tool is not selected" do
                sut = HistoricalAlertsFixedWithAutofixQuery.for_organization(
                  organization: @org,
                  user: @org_admin,
                  user_session: @user_session,
                  query: QueryParser.new("tool:secret-scanning"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                  is_open_selected: true,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 0, actual.accepted
                assert_equal 0, actual.suggested
              end
            end
          end

          context "for_business" do
            context "#perform" do
              test "it returns the correct response" do
                sut = HistoricalAlertsFixedWithAutofixQuery.for_business(
                  business: @biz,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                  user_session: @user_session,
                  authorized_orgs_by_action: [
                    :read_code_scanning,
                    :view_dependabot_alerts,
                    :view_secret_scanning_alerts,
                  ].product([[@org]]).to_h,
                  is_open_selected: true,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 2, actual.accepted
                assert_equal 12, actual.suggested
              end

              test "it filters to accessible repositories" do
                sut = HistoricalAlertsFixedWithAutofixQuery.for_business(
                  business: @biz,
                  user: @org_admin,
                  user_session: @user_session,
                  query: QueryParser.new,
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                  authorized_orgs_by_action: [
                    :read_code_scanning,
                    :view_dependabot_alerts,
                    :view_secret_scanning_alerts,
                  ].product([[@org]]).to_h,
                  is_open_selected: true,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 2, actual.accepted
                assert_equal 12, actual.suggested
              end

              test "it applies repo filters" do
                sut = HistoricalAlertsFixedWithAutofixQuery.for_business(
                  business: @biz,
                  user: @org_admin,
                  user_session: @user_session,
                  query: QueryParser.new("visibility:private"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                  authorized_orgs_by_action: [
                    :read_code_scanning,
                    :view_dependabot_alerts,
                    :view_secret_scanning_alerts,
                  ].product([[@org]]).to_h,
                  is_open_selected: true,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 1, actual.accepted
                assert_equal 6, actual.suggested
              end

              test "it applies alert filters" do
                sut = HistoricalAlertsFixedWithAutofixQuery.for_business(
                  business: @biz,
                  user: @org_admin,
                  user_session: @user_session,
                  query: QueryParser.new("severity:critical"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                  authorized_orgs_by_action: [
                    :read_code_scanning,
                    :view_dependabot_alerts,
                    :view_secret_scanning_alerts,
                  ].product([[@org]]).to_h,
                  is_open_selected: true,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 2, actual.accepted
                assert_equal 12, actual.suggested
              end

              test "it returns zero counts if code scanning tool is not selected" do
                sut = HistoricalAlertsFixedWithAutofixQuery.for_business(
                  business: @biz,
                  user: @org_admin,
                  user_session: @user_session,
                  query: QueryParser.new("tool:secret-scanning"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                  authorized_orgs_by_action: [
                    :read_code_scanning,
                    :view_dependabot_alerts,
                    :view_secret_scanning_alerts,
                  ].product([[@org]]).to_h,
                  is_open_selected: true,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 0, actual.accepted
                assert_equal 0, actual.suggested
              end
            end
          end
        end
      end
    end
  end
end
