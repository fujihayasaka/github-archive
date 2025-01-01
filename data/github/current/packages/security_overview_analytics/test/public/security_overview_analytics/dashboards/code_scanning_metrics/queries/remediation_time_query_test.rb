# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      module Queries
        class RemediationTimeQueryTest < GitHub::TestCase
          include SecurityCenter::TestFixtures
          include ::SecurityOverviewAnalytics::TestFixtures

          fixtures do
            create_business_level_fixtures

            resolved_at_time = Time.parse("2025-02-07 12:10:00 EST")
            two_days_ago = resolved_at_time - 2.days
            four_days_ago = resolved_at_time - 4.days

            five_days_ago = resolved_at_time - 5.days
            one_hour_ago = resolved_at_time - 1.hour

            yesterday_resolved_at_time = resolved_at_time - 1.day
            yesterday_alert_one_hour_ago = yesterday_resolved_at_time - 1.hour
            yesterday_alert_five_days_ago = yesterday_resolved_at_time - 5.days
            yesterday_alert_four_days_ago = yesterday_resolved_at_time - 4.days
            half_hour_ago = resolved_at_time - 0.5.hours
            forty_five_minutes_ago = resolved_at_time - 45.minutes

            date_id = 20240801
            date = Date.find_by(id: date_id) || create(:soa_date, date_value: ::Date.parse(date_id.to_s))

            [
              @org1_private_repo = create(:private_repository, owner: @org),
              @org1_public_repo = create(:public_repository, owner: @org),
              @org2_private_repo = create(:private_repository, owner: @org2),
              @org2_public_repo = create(:public_repository, owner: @org2),
            ].each do |repository|
              repository_metadata = create(:soa_repository, repository:)
              create(:soa_feature_status_revision, repository_metadata:, date:, code_scanning_enabled: true)

              [
                { has_autofix: false, alert_resolved: false, },
                { has_autofix: false, alert_resolved:  true, alert_resolved_at: resolved_at_time.iso8601.to_time.utc, alert_created_at: four_days_ago.iso8601.to_time.utc, alert_resolution: nil },
                { has_autofix: false, alert_resolved:  true, alert_resolved_at: yesterday_resolved_at_time.iso8601.to_time.utc, alert_created_at: four_days_ago.iso8601.to_time.utc, alert_resolution: nil },
                { has_autofix: false, alert_resolved:  true, alert_resolved_at: resolved_at_time.iso8601.to_time.utc, alert_created_at: half_hour_ago.iso8601.to_time.utc, alert_resolution: nil },
                { has_autofix: false, alert_resolved:  true, alert_resolved_at: resolved_at_time.iso8601.to_time.utc, alert_created_at: forty_five_minutes_ago.iso8601.to_time.utc, alert_resolution: nil },
                { has_autofix: false, alert_resolved:  true, alert_resolved_at: resolved_at_time.iso8601.to_time.utc, alert_created_at: five_days_ago.iso8601.to_time.utc, alert_resolution: nil },
                { has_autofix: true, alert_resolved:  true, alert_resolved_at: yesterday_resolved_at_time.iso8601.to_time.utc, alert_created_at: four_days_ago.iso8601.to_time.utc, alert_resolution: nil },
                { has_autofix: true, alert_resolved:  true, alert_resolved_at: resolved_at_time.iso8601.to_time.utc, alert_created_at:  two_days_ago.iso8601.to_time.utc, alert_resolution: nil },
                { has_autofix: true, alert_resolved:  true, alert_resolved_at: resolved_at_time.iso8601.to_time.utc, alert_created_at:   two_days_ago.iso8601.to_time.utc, alert_resolution: nil },
                { has_autofix: false, alert_resolved:  true, alert_resolved_at: resolved_at_time.iso8601.to_time.utc,  alert_created_at:  four_days_ago.iso8601.to_time.utc, alert_resolution: 2 },
                { has_autofix:  true, alert_resolved: false },
                { has_autofix:  true, alert_resolved:  true, alert_resolved_at: resolved_at_time.iso8601.to_time.utc, alert_created_at:  two_days_ago.iso8601.to_time.utc, alert_resolution: nil },
                { has_autofix:  true, alert_resolved:  true, alert_resolved_at: resolved_at_time.iso8601.to_time.utc, alert_created_at:  one_hour_ago.iso8601.to_time.utc, alert_resolution: nil },
                { has_autofix:  true, alert_resolved:  true, alert_resolved_at: resolved_at_time.iso8601.to_time.utc, alert_created_at:  five_days_ago.iso8601.to_time.utc, alert_resolution: nil },
                { has_autofix:  true, alert_resolved:  true, alert_resolved_at: yesterday_resolved_at_time.iso8601.to_time.utc, alert_created_at: yesterday_alert_one_hour_ago.iso8601.to_time.utc, alert_resolution: nil },
                { has_autofix:  true, alert_resolved:  true, alert_resolved_at: yesterday_resolved_at_time.iso8601.to_time.utc, alert_created_at: yesterday_alert_five_days_ago.iso8601.to_time.utc, alert_resolution: nil },
                { has_autofix:  true, alert_resolved:  true, alert_resolved_at: yesterday_resolved_at_time.iso8601.to_time.utc, alert_created_at: yesterday_alert_four_days_ago.iso8601.to_time.utc, alert_resolution: nil },
                { has_autofix:  true, alert_resolved:  true, alert_resolved_at: resolved_at_time.iso8601.to_time.utc,  alert_created_at: two_days_ago.iso8601.to_time.utc, alert_resolution: 2 },
              ].each_with_index do |scenario, idx|
                create(
                  :soa_code_scanning_pr_alert,
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
          end

          context ".for_business" do
            context "#perform" do
              test "it works" do
                sut = RemediationTimeQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 61.5556, actual.remediationTimeInHoursWithAutofixSuggested
                assert_equal 57.6, actual.remediationTimeInHoursWithNoAutofixSuggested
              end

              test "it filters to authorized organizations" do
                sut = RemediationTimeQuery.for_business(
                  business: @business,
                  organizations: [@org],
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 61.5556, actual.remediationTimeInHoursWithAutofixSuggested
                assert_equal 57.6, actual.remediationTimeInHoursWithNoAutofixSuggested
              end

              test "it returns no data when no authorized organizations" do
                sut = RemediationTimeQuery.for_business(
                  business: @business,
                  organizations: [],
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 0, actual.remediationTimeInHoursWithAutofixSuggested
                assert_equal 0, actual.remediationTimeInHoursWithNoAutofixSuggested
              end

              test "it applies repo filters" do
                sut = RemediationTimeQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("visibility:private"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 61.5556, actual.remediationTimeInHoursWithAutofixSuggested
                assert_equal 57.6, actual.remediationTimeInHoursWithNoAutofixSuggested
              end

              test "it applies alert filters" do
                sut = RemediationTimeQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("severity:critical"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 61.5556, actual.remediationTimeInHoursWithAutofixSuggested
                assert_equal 57.6, actual.remediationTimeInHoursWithNoAutofixSuggested
              end
            end
          end

          context ".for_organization" do
            context "#perform" do
              test "it works" do
                sut = RemediationTimeQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 61.5556, actual.remediationTimeInHoursWithAutofixSuggested
                assert_equal 57.6, actual.remediationTimeInHoursWithNoAutofixSuggested
              end

              test "it filters to accessible repositories" do
                sut = RemediationTimeQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: [@org1_private_repo],
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 61.5556, actual.remediationTimeInHoursWithAutofixSuggested
                assert_equal 57.6, actual.remediationTimeInHoursWithNoAutofixSuggested
              end

              test "it returns no data when no allowed repositories" do
                sut = RemediationTimeQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: [],
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 0, actual.remediationTimeInHoursWithAutofixSuggested
                assert_equal 0, actual.remediationTimeInHoursWithNoAutofixSuggested
              end

              test "it applies repo filters" do
                sut = RemediationTimeQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new("visibility:private"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 61.5556, actual.remediationTimeInHoursWithAutofixSuggested
                assert_equal 57.6, actual.remediationTimeInHoursWithNoAutofixSuggested
              end

              test "it applies alert filters" do
                sut = RemediationTimeQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new("severity:critical"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 61.5556, actual.remediationTimeInHoursWithAutofixSuggested
                assert_equal 57.6, actual.remediationTimeInHoursWithNoAutofixSuggested
              end
            end
          end
        end
      end
    end
  end
end
