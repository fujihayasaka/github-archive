# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      module Queries
        class AlertTrendsQueryByStatusTest < GitHub::TestCase
          include SecurityCenter::TestFixtures
          include ::SecurityOverviewAnalytics::TestFixtures

          fixtures do
            create_business_level_fixtures

            dates = [
              create(:soa_date, date_value: ::Date.parse("2024-07-31")),
              create(:soa_date, date_value: ::Date.parse("2024-08-01")),
              create(:soa_date, date_value: ::Date.parse("2024-08-02")),
            ]

            [
              @org1_private_repo = create(:private_repository, owner: @org),
              @org1_public_repo = create(:public_repository, owner: @org),
              @org2_private_repo = create(:private_repository, owner: @org2),
              @org2_public_repo = create(:public_repository, owner: @org2),
            ].each do |repository|
              repository_metadata = create(:soa_repository, repository:)
              create(:soa_feature_status_revision, repository_metadata:, date: dates.first, code_scanning_enabled: true)

              [
                # Unresolved
                { alert_resolved: false, alert_resolution: nil, autofix_accepted: false, },
                # Fixed with autofix
                { alert_resolved: true, alert_resolution: nil, autofix_accepted: false, },
                # Fixed without autofix
                { alert_resolved: true, alert_resolution: nil, autofix_accepted: true, },
                # Dismissed, all reasons
                { alert_resolved: true, alert_resolution: 1, autofix_accepted: false, },
                { alert_resolved: true, alert_resolution: 2, autofix_accepted: false, },
                { alert_resolved: true, alert_resolution: 3, autofix_accepted: false, },
              ].each_with_index do |scenario, idx|
                create(
                  :soa_code_scanning_pr_alert,
                  repository_metadata:,
                  alert_number: idx,
                  date_id: dates[idx % dates.length].id,
                  **scenario,
                )
              end
            end
          end

          setup do
            Timecop.freeze do
              @default_end_date = ::Date.parse("2024-08-02")
              @default_start_date = @default_end_date - 2.days
            end
          end

          context ".for_business" do
            context "#perform" do
              test "it works" do
                result = AlertTrendsQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Status)

                refute_nil result
                assert_equal 4, result.series.size

                unresolved_and_merged = T.must(result.series[0])
                assert_equal "Unresolved and merged", unresolved_and_merged.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 4),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), unresolved_and_merged.data.map(&:serialize)

                fixed_with_autofix = T.must(result.series[1])
                assert_equal "Fixed with autofix", fixed_with_autofix.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 4)
                ].map(&:serialize), fixed_with_autofix.data.map(&:serialize)

                fixed_without_autofix = T.must(result.series[2])
                assert_equal "Fixed without autofix", fixed_without_autofix.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 4),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), fixed_without_autofix.data.map(&:serialize)

                dismissed = T.must(result.series[3])
                assert_equal "Dismissed", dismissed.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 4),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 4),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 4)
                ].map(&:serialize), dismissed.data.map(&:serialize)
              end

              test "it filters to authorized organizations" do
                result = AlertTrendsQuery.for_business(
                  business: @business,
                  organizations: [@org],
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Status)

                refute_nil result
                assert_equal 4, result.series.size

                unresolved_and_merged = T.must(result.series[0])
                assert_equal "Unresolved and merged", unresolved_and_merged.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), unresolved_and_merged.data.map(&:serialize)

                fixed_with_autofix = T.must(result.series[1])
                assert_equal "Fixed with autofix", fixed_with_autofix.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 2)
                ].map(&:serialize), fixed_with_autofix.data.map(&:serialize)

                fixed_without_autofix = T.must(result.series[2])
                assert_equal "Fixed without autofix", fixed_without_autofix.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), fixed_without_autofix.data.map(&:serialize)

                dismissed = T.must(result.series[3])
                assert_equal "Dismissed", dismissed.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 2)
                ].map(&:serialize), dismissed.data.map(&:serialize)
              end

              test "it returns all zero data when no authorized organizations" do
                result = AlertTrendsQuery.for_business(
                  business: @business,
                  organizations: [],
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Status)

                refute_nil result
                assert_equal 4, result.series.size

                assert_equal [
                  "Unresolved and merged",
                  "Fixed with autofix",
                  "Fixed without autofix",
                  "Dismissed",
                ], result.series.map(&:label)

                result.series.each do |series|
                  assert_equal [
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                  ].map(&:serialize), series.data.map(&:serialize)
                end
              end

              test "it applies repo filters" do
                result = AlertTrendsQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("visibility:private"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Status)

                refute_nil result
                assert_equal 4, result.series.size

                unresolved_and_merged = T.must(result.series[0])
                assert_equal "Unresolved and merged", unresolved_and_merged.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), unresolved_and_merged.data.map(&:serialize)

                fixed_with_autofix = T.must(result.series[1])
                assert_equal "Fixed with autofix", fixed_with_autofix.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 2)
                ].map(&:serialize), fixed_with_autofix.data.map(&:serialize)

                fixed_without_autofix = T.must(result.series[2])
                assert_equal "Fixed without autofix", fixed_without_autofix.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), fixed_without_autofix.data.map(&:serialize)

                dismissed = T.must(result.series[3])
                assert_equal "Dismissed", dismissed.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 2)
                ].map(&:serialize), dismissed.data.map(&:serialize)
              end

              test "it applies alert filters" do
                result = AlertTrendsQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("severity:critical"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Status)

                refute_nil result
                assert_equal 4, result.series.size

                unresolved_and_merged = T.must(result.series[0])
                assert_equal "Unresolved and merged", unresolved_and_merged.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 4),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), unresolved_and_merged.data.map(&:serialize)

                fixed_with_autofix = T.must(result.series[1])
                assert_equal "Fixed with autofix", fixed_with_autofix.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 4)
                ].map(&:serialize), fixed_with_autofix.data.map(&:serialize)

                fixed_without_autofix = T.must(result.series[2])
                assert_equal "Fixed without autofix", fixed_without_autofix.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 4),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), fixed_without_autofix.data.map(&:serialize)

                dismissed = T.must(result.series[3])
                assert_equal "Dismissed", dismissed.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 4),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 4),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 4)
                ].map(&:serialize), dismissed.data.map(&:serialize)
              end

              test "it returns all zero data when no repos match filter" do
                result = AlertTrendsQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("repo:#{SecureRandom.uuid}"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Status)

                refute_nil result
                assert_equal 4, result.series.size

                assert_equal [
                  "Unresolved and merged",
                  "Fixed with autofix",
                  "Fixed without autofix",
                  "Dismissed",
                ], result.series.map(&:label)

                result.series.each do |series|
                  assert_equal [
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                  ].map(&:serialize), series.data.map(&:serialize)
                end
              end
            end
          end

          context ".for_organization" do
            context "#perform" do
              test "it works" do
                result = AlertTrendsQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Status)

                refute_nil result
                assert_equal 4, result.series.size

                unresolved_and_merged = T.must(result.series[0])
                assert_equal "Unresolved and merged", unresolved_and_merged.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), unresolved_and_merged.data.map(&:serialize)

                fixed_with_autofix = T.must(result.series[1])
                assert_equal "Fixed with autofix", fixed_with_autofix.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 2)
                ].map(&:serialize), fixed_with_autofix.data.map(&:serialize)

                fixed_without_autofix = T.must(result.series[2])
                assert_equal "Fixed without autofix", fixed_without_autofix.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), fixed_without_autofix.data.map(&:serialize)

                dismissed = T.must(result.series[3])
                assert_equal "Dismissed", dismissed.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 2)
                ].map(&:serialize), dismissed.data.map(&:serialize)
              end

              test "it filters to accessible repositories" do
                result = AlertTrendsQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: [@org1_private_repo],
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Status)

                refute_nil result
                assert_equal 4, result.series.size

                unresolved_and_merged = T.must(result.series[0])
                assert_equal "Unresolved and merged", unresolved_and_merged.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 1),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), unresolved_and_merged.data.map(&:serialize)

                fixed_with_autofix = T.must(result.series[1])
                assert_equal "Fixed with autofix", fixed_with_autofix.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 1)
                ].map(&:serialize), fixed_with_autofix.data.map(&:serialize)

                fixed_without_autofix = T.must(result.series[2])
                assert_equal "Fixed without autofix", fixed_without_autofix.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 1),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), fixed_without_autofix.data.map(&:serialize)

                dismissed = T.must(result.series[3])
                assert_equal "Dismissed", dismissed.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 1),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 1),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 1)
                ].map(&:serialize), dismissed.data.map(&:serialize)
              end

              test "it returns all zero data when no allowed repositories" do
                result = AlertTrendsQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: [],
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Status)

                refute_nil result
                assert_equal 4, result.series.size

                assert_equal [
                  "Unresolved and merged",
                  "Fixed with autofix",
                  "Fixed without autofix",
                  "Dismissed",
                ], result.series.map(&:label)

                result.series.each do |series|
                  assert_equal [
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                  ].map(&:serialize), series.data.map(&:serialize)
                end
              end

              test "it applies repo filters" do
                result = AlertTrendsQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new("visibility:private"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Status)

                refute_nil result
                assert_equal 4, result.series.size

                unresolved_and_merged = T.must(result.series[0])
                assert_equal "Unresolved and merged", unresolved_and_merged.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 1),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), unresolved_and_merged.data.map(&:serialize)

                fixed_with_autofix = T.must(result.series[1])
                assert_equal "Fixed with autofix", fixed_with_autofix.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 1)
                ].map(&:serialize), fixed_with_autofix.data.map(&:serialize)

                fixed_without_autofix = T.must(result.series[2])
                assert_equal "Fixed without autofix", fixed_without_autofix.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 1),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), fixed_without_autofix.data.map(&:serialize)

                dismissed = T.must(result.series[3])
                assert_equal "Dismissed", dismissed.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 1),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 1),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 1)
                ].map(&:serialize), dismissed.data.map(&:serialize)
              end

              test "it applies alert filters" do
                result = AlertTrendsQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new("severity:critical"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Status)

                refute_nil result
                assert_equal 4, result.series.size

                unresolved_and_merged = T.must(result.series[0])
                assert_equal "Unresolved and merged", unresolved_and_merged.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), unresolved_and_merged.data.map(&:serialize)

                fixed_with_autofix = T.must(result.series[1])
                assert_equal "Fixed with autofix", fixed_with_autofix.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 2)
                ].map(&:serialize), fixed_with_autofix.data.map(&:serialize)

                fixed_without_autofix = T.must(result.series[2])
                assert_equal "Fixed without autofix", fixed_without_autofix.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), fixed_without_autofix.data.map(&:serialize)

                dismissed = T.must(result.series[3])
                assert_equal "Dismissed", dismissed.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 2)
                ].map(&:serialize), dismissed.data.map(&:serialize)
              end

              test "it returns all zero data when no repos match filter" do
                result = AlertTrendsQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new("repo:#{SecureRandom.uuid}"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Status)

                refute_nil result
                assert_equal 4, result.series.size

                assert_equal [
                  "Unresolved and merged",
                  "Fixed with autofix",
                  "Fixed without autofix",
                  "Dismissed",
                ], result.series.map(&:label)

                result.series.each do |series|
                  assert_equal [
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                  ].map(&:serialize), series.data.map(&:serialize)
                end
              end
            end
          end
        end

        class AlertTrendsQueryBySeverityTest < GitHub::TestCase
          include SecurityCenter::TestFixtures
          include ::SecurityOverviewAnalytics::TestFixtures

          fixtures do
            create_business_level_fixtures

            dates = [
              create(:soa_date, date_value: ::Date.parse("2024-07-31")),
              create(:soa_date, date_value: ::Date.parse("2024-08-01")),
              create(:soa_date, date_value: ::Date.parse("2024-08-02")),
            ]

            [
              @org1_private_repo = create(:private_repository, owner: @org),
              @org1_public_repo = create(:public_repository, owner: @org),
              @org2_private_repo = create(:private_repository, owner: @org2),
              @org2_public_repo = create(:public_repository, owner: @org2),
            ].each do |repository|
              repository_metadata = create(:soa_repository, repository:)
              create(:soa_feature_status_revision, repository_metadata:, date: dates.first, code_scanning_enabled: true)

              [
                { alert_severity: "critical" },
                { alert_severity: "high" },
                { alert_severity: "medium" },
                { alert_severity: "low" },
                { alert_severity: "error" },
                { alert_severity: "warning" },
                { alert_severity: "note" },
                { alert_severity: nil },
              ].each_with_index do |scenario, idx|
                create(
                  :soa_code_scanning_pr_alert,
                  repository_metadata:,
                  alert_number: idx,
                  date_id: dates[idx % dates.length].id,
                  **scenario,
                )
              end
            end
          end

          setup do
            Timecop.freeze do
              @default_end_date = ::Date.parse("2024-08-02")
              @default_start_date = @default_end_date - 2.days
            end
          end

          context ".for_business" do
            context "#perform" do
              test "it works" do
                result = AlertTrendsQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Severity)

                refute_nil result
                assert_equal 4, result.series.size

                critical = T.must(result.series[0])
                assert_equal "Critical", critical.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 4),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), critical.data.map(&:serialize)

                high = T.must(result.series[1])
                assert_equal "High", high.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 4),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), high.data.map(&:serialize)

                medium = T.must(result.series[2])
                assert_equal "Medium", medium.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 4)
                ].map(&:serialize), medium.data.map(&:serialize)

                low = T.must(result.series[3])
                assert_equal "Low", low.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 4),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), low.data.map(&:serialize)
              end

              test "it filters to authorized organizations" do
                result = AlertTrendsQuery.for_business(
                  business: @business,
                  organizations: [@org],
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Severity)

                refute_nil result
                assert_equal 4, result.series.size

                critical = T.must(result.series[0])
                assert_equal "Critical", critical.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), critical.data.map(&:serialize)

                high = T.must(result.series[1])
                assert_equal "High", high.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), high.data.map(&:serialize)

                medium = T.must(result.series[2])
                assert_equal "Medium", medium.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 2)
                ].map(&:serialize), medium.data.map(&:serialize)

                low = T.must(result.series[3])
                assert_equal "Low", low.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), low.data.map(&:serialize)
              end

              test "it returns all zero data when no authorized organizations" do
                result = AlertTrendsQuery.for_business(
                  business: @business,
                  organizations: [],
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Severity)

                refute_nil result
                assert_equal 4, result.series.size

                assert_equal %w[
                  Critical
                  High
                  Medium
                  Low
                ], result.series.map(&:label)

                result.series.each do |series|
                  assert_equal [
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                  ].map(&:serialize), series.data.map(&:serialize)
                end
              end

              test "it applies repo filters" do
                result = AlertTrendsQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("visibility:private"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Severity)

                refute_nil result
                assert_equal 4, result.series.size

                critical = T.must(result.series[0])
                assert_equal "Critical", critical.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), critical.data.map(&:serialize)

                high = T.must(result.series[1])
                assert_equal "High", high.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), high.data.map(&:serialize)

                medium = T.must(result.series[2])
                assert_equal "Medium", medium.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 2)
                ].map(&:serialize), medium.data.map(&:serialize)

                low = T.must(result.series[3])
                assert_equal "Low", low.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), low.data.map(&:serialize)
              end

              test "it applies alert filters" do
                result = AlertTrendsQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("severity:critical"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Severity)

                refute_nil result
                assert_equal 4, result.series.size

                critical = T.must(result.series[0])
                assert_equal "Critical", critical.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 4),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), critical.data.map(&:serialize)

                high = T.must(result.series[1])
                assert_equal "High", high.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), high.data.map(&:serialize)

                medium = T.must(result.series[2])
                assert_equal "Medium", medium.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), medium.data.map(&:serialize)

                low = T.must(result.series[3])
                assert_equal "Low", low.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), low.data.map(&:serialize)
              end

              test "it returns all zero data when no repos match filter" do
                result = AlertTrendsQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("repo:#{SecureRandom.uuid}"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Severity)

                refute_nil result
                assert_equal 4, result.series.size

                assert_equal %w[
                  Critical
                  High
                  Medium
                  Low
                ], result.series.map(&:label)

                result.series.each do |series|
                  assert_equal [
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                  ].map(&:serialize), series.data.map(&:serialize)
                end
              end
            end
          end

          context ".for_organization" do
            context "#perform" do
              test "it works" do
                result = AlertTrendsQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Severity)

                refute_nil result
                assert_equal 4, result.series.size

                critical = T.must(result.series[0])
                assert_equal "Critical", critical.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), critical.data.map(&:serialize)

                high = T.must(result.series[1])
                assert_equal "High", high.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), high.data.map(&:serialize)

                medium = T.must(result.series[2])
                assert_equal "Medium", medium.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 2)
                ].map(&:serialize), medium.data.map(&:serialize)

                low = T.must(result.series[3])
                assert_equal "Low", low.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), low.data.map(&:serialize)
              end

              test "it filters to accessible repositories" do
                result = AlertTrendsQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: [@org1_private_repo],
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Severity)

                refute_nil result
                assert_equal 4, result.series.size

                critical = T.must(result.series[0])
                assert_equal "Critical", critical.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 1),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), critical.data.map(&:serialize)

                high = T.must(result.series[1])
                assert_equal "High", high.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 1),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), high.data.map(&:serialize)

                medium = T.must(result.series[2])
                assert_equal "Medium", medium.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 1)
                ].map(&:serialize), medium.data.map(&:serialize)

                low = T.must(result.series[3])
                assert_equal "Low", low.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 1),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), low.data.map(&:serialize)
              end

              test "it returns all zero data when no allowed repositories" do
                result = AlertTrendsQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: [],
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Severity)

                refute_nil result
                assert_equal 4, result.series.size

                assert_equal %w[
                  Critical
                  High
                  Medium
                  Low
                ], result.series.map(&:label)

                result.series.each do |series|
                  assert_equal [
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                  ].map(&:serialize), series.data.map(&:serialize)
                end
              end

              test "it applies repo filters" do
                result = AlertTrendsQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new("visibility:private"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Severity)

                refute_nil result
                assert_equal 4, result.series.size

                critical = T.must(result.series[0])
                assert_equal "Critical", critical.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 1),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), critical.data.map(&:serialize)

                high = T.must(result.series[1])
                assert_equal "High", high.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 1),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), high.data.map(&:serialize)

                medium = T.must(result.series[2])
                assert_equal "Medium", medium.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 1)
                ].map(&:serialize), medium.data.map(&:serialize)

                low = T.must(result.series[3])
                assert_equal "Low", low.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 1),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), low.data.map(&:serialize)
              end

              test "it applies alert filters" do
                result = AlertTrendsQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new("severity:critical"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Severity)

                refute_nil result
                assert_equal 4, result.series.size

                critical = T.must(result.series[0])
                assert_equal "Critical", critical.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), critical.data.map(&:serialize)

                high = T.must(result.series[1])
                assert_equal "High", high.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), high.data.map(&:serialize)

                medium = T.must(result.series[2])
                assert_equal "Medium", medium.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), medium.data.map(&:serialize)

                low = T.must(result.series[3])
                assert_equal "Low", low.label
                assert_equal [
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                  AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                ].map(&:serialize), low.data.map(&:serialize)
              end

              test "it returns all zero data when no repos match filter" do
                result = AlertTrendsQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new("repo:#{SecureRandom.uuid}"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform(group_by: AlertTrendsQuery::GroupOption::Severity)

                refute_nil result
                assert_equal 4, result.series.size

                assert_equal %w[
                  Critical
                  High
                  Medium
                  Low
                ], result.series.map(&:label)

                result.series.each do |series|
                  assert_equal [
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240801"), y: 0),
                    AlertTrendsQuery::DataPoint.new(x: ::Date.parse("20240802"), y: 0)
                  ].map(&:serialize), series.data.map(&:serialize)
                end
              end
            end
          end
        end
      end
    end
  end
end
