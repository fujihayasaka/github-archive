# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AlertsFixedWithAutofixQueryTest < GitHub::TestCase
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
                sut = AlertsFixedWithAutofixQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 4, actual.accepted
                assert_equal 24, actual.suggested
              end

              test "it filters to authorized organizations" do
                sut = AlertsFixedWithAutofixQuery.for_business(
                  business: @business,
                  organizations: [@org],
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 2, actual.accepted
                assert_equal 12, actual.suggested
              end

              test "it applies repo filters" do
                sut = AlertsFixedWithAutofixQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("visibility:private"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 2, actual.accepted
                assert_equal 12, actual.suggested
              end

              test "it applies alert filters" do
                sut = AlertsFixedWithAutofixQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("severity:critical"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 4, actual.accepted
                assert_equal 24, actual.suggested
              end

              test "it returns zero counts if codeql is not selected in the tool list" do
                sut = AlertsFixedWithAutofixQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("tool:secret-scanning"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 0, actual.accepted
                assert_equal 0, actual.suggested
              end

              test "it returns zero counts if non-codeql filters are applied" do
                sut = AlertsFixedWithAutofixQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("third-party.rule:foo"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 0, actual.accepted
                assert_equal 0, actual.suggested
              end
            end
          end

          context ".for_organization" do
            context "#perform" do
              test "it works" do
                sut = AlertsFixedWithAutofixQuery.for_organization(
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
                assert_equal 2, actual.accepted
                assert_equal 12, actual.suggested
              end

              test "it filters to accessible repositories" do
                sut = AlertsFixedWithAutofixQuery.for_organization(
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
                assert_equal 0, actual.accepted
                assert_equal 0, actual.suggested
              end

              test "it applies repo filters" do
                sut = AlertsFixedWithAutofixQuery.for_organization(
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
                assert_equal 1, actual.accepted
                assert_equal 6, actual.suggested
              end

              test "it applies alert filters" do
                sut = AlertsFixedWithAutofixQuery.for_organization(
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
                assert_equal 2, actual.accepted
                assert_equal 12, actual.suggested
              end

              test "it returns zero counts if codeql is not selected in the tool list" do
                sut = AlertsFixedWithAutofixQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new("tool:secret-scanning"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 0, actual.accepted
                assert_equal 0, actual.suggested
              end

              test "it returns zero counts if non-codeql filters are applied" do
                sut = AlertsFixedWithAutofixQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new("third-party.rule:foo"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
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
