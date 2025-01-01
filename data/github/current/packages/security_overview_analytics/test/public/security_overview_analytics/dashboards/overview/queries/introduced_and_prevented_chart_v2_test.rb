# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class IntroducedAndPreventedChartV2Test < GitHub::TestCase
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
                { alert_resolved: false, alert_resolution: nil, autofix_accepted: false, }, # introduced
                # Prevented
                { alert_resolved: true, alert_resolution: nil, autofix_accepted: false, }, # prevented
                # Fixed without autofix
                { alert_resolved: true, alert_resolution: nil, autofix_accepted: true, }, # prevented
                # Dismissed, all reasons
                { alert_resolved: true, alert_resolution: 1, autofix_accepted: false, }, # false_positive; excluded
                { alert_resolved: true, alert_resolution: 2, autofix_accepted: false, }, # risk_accepted; introduced
                { alert_resolved: true, alert_resolution: 3, autofix_accepted: false, }, # risk_accepted; introduced
              ].each_with_index do |scenario, idx|
                date_id = dates[idx % dates.length].id
                create(
                  :soa_code_scanning_pr_alert,
                  repository_metadata:,
                  alert_number: idx,
                  date_id:,
                  alert_resolved_at: scenario[:alert_resolved] ? Time.parse("2024-07-31") : nil,
                  alert_updated_at: Time.parse("2024-08-2"),
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
                result = IntroducedAndPreventedChartV2.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform

                refute_nil result
                assert_equal 2, result.series.size

                introduced = T.must(result.series[0])
                assert_equal "Introduced", introduced.label
                assert_equal [
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240731"), y: 4),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240801"), y: 8),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240802"), y: 12)
                ].map(&:serialize), introduced.data.map(&:serialize)

                prevented = T.must(result.series[1])
                assert_equal "Prevented", prevented.label
                assert_equal [
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240801"), y: 4),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240802"), y: 8)
                ].map(&:serialize), prevented.data.map(&:serialize)
              end

              test "it filters to authorized organizations" do
                result = IntroducedAndPreventedChartV2.for_business(
                  business: @business,
                  organizations: [@org],
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform

                refute_nil result
                assert_equal 2, result.series.size

                introduced = T.must(result.series[0])
                assert_equal "Introduced", introduced.label
                assert_equal [
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240801"), y: 4),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240802"), y: 6)
                ].map(&:serialize), introduced.data.map(&:serialize)

                prevented = T.must(result.series[1])
                assert_equal "Prevented", prevented.label
                assert_equal [
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240801"), y: 2),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240802"), y: 4)
                ].map(&:serialize), prevented.data.map(&:serialize)
              end

              test "it returns empty data when no authorized organizations" do
                result = IntroducedAndPreventedChartV2.for_business(
                  business: @business,
                  organizations: [],
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform

                refute_nil result
                assert_empty result.series
              end

              test "it applies repo filters" do
                result = IntroducedAndPreventedChartV2.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("visibility:private"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform

                refute_nil result
                assert_equal 2, result.series.size

                introduced = T.must(result.series[0])
                assert_equal "Introduced", introduced.label
                assert_equal [
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240801"), y: 4),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240802"), y: 6)
                ].map(&:serialize), introduced.data.map(&:serialize)

                prevented = T.must(result.series[1])
                assert_equal "Prevented", prevented.label
                assert_equal [
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240801"), y: 2),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240802"), y: 4)
                ].map(&:serialize), prevented.data.map(&:serialize)
              end

              test "it applies alert filters" do
                result = IntroducedAndPreventedChartV2.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("severity:critical"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform

                refute_nil result
                assert_equal 2, result.series.size

                introduced = T.must(result.series[0])
                assert_equal "Introduced", introduced.label
                assert_equal [
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240731"), y: 4),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240801"), y: 8),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240802"), y: 12)
                ].map(&:serialize), introduced.data.map(&:serialize)

                prevented = T.must(result.series[1])
                assert_equal "Prevented", prevented.label
                assert_equal [
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240801"), y: 4),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240802"), y: 8)
                ].map(&:serialize), prevented.data.map(&:serialize)
              end

              test "it returns empty data when no repos match filter" do
                result = IntroducedAndPreventedChartV2.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("repo:#{SecureRandom.uuid}"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform

                refute_nil result
                assert_empty result.series
              end
            end
          end

          context ".for_organization" do
            context "#perform" do
              test "it works" do
                result = IntroducedAndPreventedChartV2.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform

                refute_nil result
                assert_equal 2, result.series.size

                introduced = T.must(result.series[0])
                assert_equal "Introduced", introduced.label
                assert_equal [
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240801"), y: 4),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240802"), y: 6)
                ].map(&:serialize), introduced.data.map(&:serialize)

                prevented = T.must(result.series[1])
                assert_equal "Prevented", prevented.label
                assert_equal [
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240801"), y: 2),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240802"), y: 4)
                ].map(&:serialize), prevented.data.map(&:serialize)
              end

              test "includes alert data prior to start date" do
                result = IntroducedAndPreventedChartV2.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date + 1.day,
                  end_date: @default_end_date,
                ).perform

                refute_nil result
                assert_equal 2, result.series.size

                introduced = T.must(result.series[0])
                assert_equal "Introduced", introduced.label
                assert_equal [
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240801"), y: 4),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240802"), y: 6)
                ].map(&:serialize), introduced.data.map(&:serialize)

                prevented = T.must(result.series[1])
                assert_equal "Prevented", prevented.label
                assert_equal [
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240801"), y: 2),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240802"), y: 4)
                ].map(&:serialize), prevented.data.map(&:serialize)
              end

              test "it filters to accessible repositories" do
                result = IntroducedAndPreventedChartV2.for_organization(
                  organization: @org,
                  allowed_repo_ids: [@org1_private_repo],
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform

                refute_nil result
                assert_equal 2, result.series.size

                introduced = T.must(result.series[0])
                assert_equal "Introduced", introduced.label
                assert_equal [
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240731"), y: 1),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240801"), y: 2),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240802"), y: 3)
                ].map(&:serialize), introduced.data.map(&:serialize)

                prevented = T.must(result.series[1])
                assert_equal "Prevented", prevented.label
                assert_equal [
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240801"), y: 1),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240802"), y: 2)
                ].map(&:serialize), prevented.data.map(&:serialize)
              end

              test "it returns empty data when no allowed repositories" do
                result = IntroducedAndPreventedChartV2.for_organization(
                  organization: @org,
                  allowed_repo_ids: [],
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform

                refute_nil result
                assert_empty result.series
              end

              test "it applies repo filters" do
                result = IntroducedAndPreventedChartV2.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new("visibility:private"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform

                refute_nil result
                assert_equal 2, result.series.size

                introduced = T.must(result.series[0])
                assert_equal "Introduced", introduced.label
                assert_equal [
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240731"), y: 1),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240801"), y: 2),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240802"), y: 3)
                ].map(&:serialize), introduced.data.map(&:serialize)

                prevented = T.must(result.series[1])
                assert_equal "Prevented", prevented.label
                assert_equal [
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240801"), y: 1),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240802"), y: 2)
                ].map(&:serialize), prevented.data.map(&:serialize)
              end

              test "it applies alert filters" do
                result = IntroducedAndPreventedChartV2.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new("severity:critical"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform

                refute_nil result
                assert_equal 2, result.series.size

                introduced = T.must(result.series[0])
                assert_equal "Introduced", introduced.label
                assert_equal [
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240731"), y: 2),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240801"), y: 4),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240802"), y: 6)
                ].map(&:serialize), introduced.data.map(&:serialize)

                prevented = T.must(result.series[1])
                assert_equal "Prevented", prevented.label
                assert_equal [
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240731"), y: 0),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240801"), y: 2),
                  IntroducedAndPreventedChartV2::DataPoint.new(x: ::Date.parse("20240802"), y: 4)
                ].map(&:serialize), prevented.data.map(&:serialize)
              end

              test "it returns empty data when no repos match filter" do
                result = IntroducedAndPreventedChartV2.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new("repo:#{SecureRandom.uuid}"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                ).perform

                refute_nil result
                assert_empty result.series
              end
            end
          end
        end
      end
    end
  end
end
