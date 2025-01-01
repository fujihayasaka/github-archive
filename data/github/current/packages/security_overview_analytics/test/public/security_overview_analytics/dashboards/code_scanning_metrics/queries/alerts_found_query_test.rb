# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      module Queries
        class AlertsFoundQueryTest < GitHub::TestCase
          include SecurityCenter::TestFixtures
          include ::SecurityOverviewAnalytics::TestFixtures

          fixtures do
            create_business_level_fixtures

            date_id = 20240801
            date = Date.find_by(id: date_id) || create(:soa_date, date_value: ::Date.parse(date_id.to_s))

            [
              create(:private_repository, owner: @org),
              create(:public_repository, owner: @org),
              create(:private_repository, owner: @org2),
              create(:public_repository, owner: @org2),
            ].each_with_index do |repository, idx|
              repository_metadata = create(:soa_repository, repository:)
              create(:soa_feature_status_revision, repository_metadata:, date:, code_scanning_enabled: true)

              # alert resolved in PR
              create(
                :soa_code_scanning_pr_alert,
                repository_metadata:,
                alert_number: 100 + idx,
                date_id:,
                alert_resolved: true,
                alert_resolution: nil,
                tool: "CodeQL",
                alert_severity: "critical",
                alert_created_at: ::Date.parse(date_id.to_s),
              )

              # alert unresolved in PR and later found in default branch
              unresolved = create(
                :soa_code_scanning_pr_alert,
                repository_metadata:,
                alert_number: 200 + idx,
                date_id:,
                alert_resolved: false,
                alert_resolution: nil,
                tool: "CodeQL",
                alert_severity: "medium",
                alert_created_at: ::Date.parse(date_id.to_s),
              )
              create(
                :soa_code_scanning_alert_revision,
                repository_metadata:,
                date_id:,
                alert_number: unresolved.alert_number,
                alert_resolved: unresolved.alert_resolved,
                alert_severity: unresolved.alert_severity,
                tool: unresolved.tool,
                rule_sarif_identifier: unresolved.rule_sarif_identifier,
                alert_created_at: unresolved.alert_created_at,
                alert_updated_at: unresolved.alert_updated_at,
              )

              # alert on default branch from non-PR source
              create(
                :soa_code_scanning_alert_revision,
                repository_metadata:,
                date_id:,
                alert_number: 300 + idx,
                alert_resolved: false,
                alert_severity: "low",
                alert_created_at: ::Date.parse(date_id.to_s),
              )
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
                sut = AlertsFoundQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 8, actual.count
              end

              test "it filters to authorized organizations" do
                sut = AlertsFoundQuery.for_business(
                  business: @business,
                  organizations: [@org],
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 4, actual.count
              end

              test "it applies repo filters" do
                sut = AlertsFoundQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("visibility:private"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 4, actual.count
              end

              test "it applies alert filters" do
                sut = AlertsFoundQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("severity:critical"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 4, actual.count
              end
            end
          end

          context ".for_organization" do
            context "#perform" do
              test "it works" do
                sut = AlertsFoundQuery.for_organization(
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
                assert_equal 4, actual.count
              end

              test "it filters to accessible repositories" do
                sut = AlertsFoundQuery.for_organization(
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
                assert_equal 0, actual.count
              end

              test "it applies repo filters" do
                sut = AlertsFoundQuery.for_organization(
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
                assert_equal 2, actual.count
              end

              test "it applies alert filters" do
                sut = AlertsFoundQuery.for_organization(
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
                assert_equal 2, actual.count
              end
            end
          end
        end
      end
    end
  end
end
