# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      module Queries
        class RepositoriesTableQueryTest < GitHub::TestCase
          include DogstatsTestHelpers
          include SecurityCenter::TestFixtures
          include ::SecurityOverviewAnalytics::TestFixtures

          fixtures do
            create_business_level_fixtures

            date_id = 20240801
            @date = Date.find_by(id: date_id) || create(:soa_date, date_value: ::Date.parse(date_id.to_s))

            [
              @org1_repo01 = create(:private_repository,  owner: @org,  name: "org1-repo01"),
              @org1_repo02 = create(:private_repository,  owner: @org,  name: "org1-repo02"),
              @org1_repo03 = create(:private_repository,  owner: @org,  name: "org1-repo03"),
              @org1_repo04 = create(:private_repository,  owner: @org,  name: "org1-repo04"),
              @org1_repo05 = create(:internal_repository, owner: @org,  name: "org1-repo05"),
              @org1_repo06 = create(:internal_repository, owner: @org,  name: "org1-repo06"),
              @org1_repo07 = create(:internal_repository, owner: @org,  name: "org1-repo07"),
              @org1_repo08 = create(:internal_repository, owner: @org,  name: "org1-repo08"),
              @org1_repo09 = create(:public_repository,   owner: @org,  name: "org1-repo09"),
              @org1_repo10 = create(:public_repository,   owner: @org,  name: "org1-repo10"),
              @org1_repo11 = create(:public_repository,   owner: @org,  name: "org1-repo11"),
              @org1_repo12 = create(:public_repository,   owner: @org,  name: "org1-repo12"),

              @org2_repo01 = create(:private_repository,  owner: @org2, name: "org2-repo01"),
              @org2_repo02 = create(:internal_repository, owner: @org2, name: "org2-repo02"),
              @org2_repo03 = create(:public_repository,   owner: @org2, name: "org2-repo03"),

              @org3_repo01 = create(:private_repository,  owner: @org3, name: "org3-repo01"),
              @org3_repo02 = create(:internal_repository, owner: @org3, name: "org3-repo02"),
              @org3_repo03 = create(:public_repository,   owner: @org3, name: "org3-repo03"),
            ].flatten.each do |repository|
              repository_metadata = create(:soa_repository, repository:)
              create(:soa_feature_status_revision, repository_metadata:, date: @date, code_scanning_enabled: true)

              [
                # Unresolved
                { alert_resolved: false, alert_resolution: nil, autofix_accepted: false, },
                # Fixed with autofix
                { alert_resolved: true, alert_resolution: nil, autofix_accepted: false, },
                # Fixed without autofix
                { alert_resolved: true, alert_resolution: nil, autofix_accepted: true, },
                # Dismissed, all variations
                { alert_resolved: true, alert_resolution: 1, autofix_accepted: false, },
                { alert_resolved: true, alert_resolution: 2, autofix_accepted: false, },
                { alert_resolved: true, alert_resolution: 3, autofix_accepted: false, },
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
                sut = RepositoriesTableQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  sort_field: RepositoriesTableQuery::SortField::UNRESOLVED,
                  sort_direction: RepositoriesTableQuery::SortDirection::DESC,
                )

                refute_nil actual
                assert_items @business, actual.items, [
                  { repo: @org3_repo03, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org3_repo02, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org3_repo01, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org2_repo03, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org2_repo02, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org2_repo01, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo12, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo11, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo10, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo09, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                ]
                assert_nil actual.previous
                assert_equal "10", actual.next
              end

              test "it filters to authorized organizations" do
                sut = RepositoriesTableQuery.for_business(
                  business: @business,
                  organizations: [@org2, @org3],
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  sort_field: RepositoriesTableQuery::SortField::UNRESOLVED,
                  sort_direction: RepositoriesTableQuery::SortDirection::DESC,
                )

                refute_nil actual
                assert_items @business, actual.items, [
                  { repo: @org3_repo03, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org3_repo02, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org3_repo01, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org2_repo03, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org2_repo02, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org2_repo01, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                ]
                assert_nil actual.previous
                assert_nil actual.next
              end

              test "it returns no data when no authorized organizations" do
                sut = RepositoriesTableQuery.for_business(
                  business: @business,
                  organizations: [],
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  sort_field: RepositoriesTableQuery::SortField::UNRESOLVED,
                  sort_direction: RepositoriesTableQuery::SortDirection::DESC,
                )

                refute_nil actual
                assert_empty actual.items
                assert_nil actual.previous
                assert_nil actual.next
              end

              test "it applies repo filters" do
                sut = RepositoriesTableQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("visibility:private"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  sort_field: RepositoriesTableQuery::SortField::UNRESOLVED,
                  sort_direction: RepositoriesTableQuery::SortDirection::DESC,
                )

                refute_nil actual
                assert_items @business, actual.items, [
                  { repo: @org3_repo01, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org2_repo01, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo04, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo03, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo02, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo01, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                ]
                assert_nil actual.previous
                assert_nil actual.next
              end

              test "it applies alert filters" do
                sut = RepositoriesTableQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("severity:critical"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  sort_field: RepositoriesTableQuery::SortField::UNRESOLVED,
                  sort_direction: RepositoriesTableQuery::SortDirection::DESC,
                )

                refute_nil actual
                assert_items @business, actual.items, [
                  { repo: @org3_repo03, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org3_repo02, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org3_repo01, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org2_repo03, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org2_repo02, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org2_repo01, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo12, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo11, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo10, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo09, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                ]
                assert_nil actual.previous
                assert_equal "10", actual.next
              end

              test "it handles pagination" do
                sut = RepositoriesTableQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "4",
                  sort_field: RepositoriesTableQuery::SortField::UNRESOLVED,
                  sort_direction: RepositoriesTableQuery::SortDirection::DESC,
                )

                refute_nil actual
                assert_items @business, actual.items, [
                  { repo: @org2_repo02, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org2_repo01, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo12, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo11, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo10, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo09, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo08, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo07, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo06, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo05, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                ]
                assert_equal "0", actual.previous
                assert_equal "14", actual.next
              end

              test "it handles sorting" do
                sut = RepositoriesTableQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  sort_field: RepositoriesTableQuery::SortField::FIXED_WO_AUTOFIX,
                  sort_direction: RepositoriesTableQuery::SortDirection::ASC,
                )

                refute_nil actual
                assert_items @business, actual.items, [
                  { repo: @org1_repo01, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo02, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo03, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo04, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo05, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo06, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo07, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo08, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo09, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo10, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                ]
                assert_nil actual.previous
                assert_equal "10", actual.next
              end

              test "it applies tenant filtering", skip_enterprise: true do
                user = create(:user)
                biz1 = create(:business)
                biz1.add_owner(user, actor: nil)
                org1 = create(:business_plus_organization, business: biz1)
                org1.add_admin(@orgs_owner)
                biz2 = create(:business)
                biz2.add_owner(user, actor: nil)
                org2 = create(:business_plus_organization, business: biz2)
                org2.add_admin(@orgs_owner)

                # Create the repository under biz2/org2
                repository = create(:private_repository, owner: org2)

                # Create our version of repository with biz1/org1 - we're out of date
                repository_metadata = create(:soa_repository, repository:, owner_id: org1.id, business_id: biz1.id)

                create(:soa_feature_status_revision, repository_metadata:, date: @date, code_scanning_enabled: true)
                pull_request = create(:pull_request, :merged, :disable_disk_access, repository:, user: @orgs_owner)

                create(
                  :soa_code_scanning_pr_alert,
                  repository_metadata:,
                  pull_request_id: pull_request.id,
                  alert_number: 1,
                  date_id: @date.id,
                  alert_updated_at: @date.date_value.to_time,
                )

                sut = RepositoriesTableQuery.for_business(
                  business: biz1,
                  organizations: [org1],
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  sort_field: RepositoriesTableQuery::SortField::UNRESOLVED,
                  sort_direction: RepositoriesTableQuery::SortDirection::DESC,
                )

                # Since the repository now belongs to org2, it
                # should have been filtered from these results
                refute_nil actual
                assert_empty actual.items
                assert_nil actual.next

                assert_dogstats_increment(1, "security_center.access_violation", tags: [
                  "feature:codeql-report",
                  "scope:business",
                  "violation:repository_out_of_scope"
                ])
              end
            end
          end

          context ".for_organization" do
            context "#perform" do
              test "it works" do
                sut = RepositoriesTableQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  sort_field: RepositoriesTableQuery::SortField::UNRESOLVED,
                  sort_direction: RepositoriesTableQuery::SortDirection::DESC,
                )

                refute_nil actual
                assert_items @org, actual.items, [
                  { repo: @org1_repo12, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo11, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo10, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo09, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo08, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo07, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo06, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo05, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo04, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo03, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                ]
                assert_nil actual.previous
                assert_equal "10", actual.next
              end

              test "it filters to accessible repositories" do
                sut = RepositoriesTableQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: [@org1_repo01, @org1_repo02, @org1_repo03],
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  sort_field: RepositoriesTableQuery::SortField::UNRESOLVED,
                  sort_direction: RepositoriesTableQuery::SortDirection::DESC,
                )

                refute_nil actual
                assert_items @org, actual.items, [
                  { repo: @org1_repo03, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo02, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo01, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                ]
                assert_nil actual.previous
                assert_nil actual.next
              end

              test "it returns no data when no allowed repositories" do
                sut = RepositoriesTableQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: [],
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  sort_field: RepositoriesTableQuery::SortField::UNRESOLVED,
                  sort_direction: RepositoriesTableQuery::SortDirection::DESC,
                )

                refute_nil actual
                assert_empty actual.items
                assert_nil actual.previous
                assert_nil actual.next
              end

              test "it applies repo filters" do
                sut = RepositoriesTableQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new("visibility:private"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  sort_field: RepositoriesTableQuery::SortField::UNRESOLVED,
                  sort_direction: RepositoriesTableQuery::SortDirection::DESC,
                )

                refute_nil actual
                assert_items @org, actual.items, [
                  { repo: @org1_repo04, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo03, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo02, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo01, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                ]
                assert_nil actual.previous
                assert_nil actual.next
              end

              test "it applies alert filters" do
                sut = RepositoriesTableQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new("severity:critical"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  sort_field: RepositoriesTableQuery::SortField::UNRESOLVED,
                  sort_direction: RepositoriesTableQuery::SortDirection::DESC,
                )

                refute_nil actual
                assert_items @org, actual.items, [
                  { repo: @org1_repo12, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo11, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo10, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo09, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo08, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo07, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo06, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo05, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo04, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo03, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                ]
                assert_nil actual.previous
                assert_equal "10", actual.next
              end

              test "it handles pagination" do
                sut = RepositoriesTableQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "4",
                  sort_field: RepositoriesTableQuery::SortField::UNRESOLVED,
                  sort_direction: RepositoriesTableQuery::SortDirection::DESC,
                )

                refute_nil actual
                assert_items @org, actual.items, [
                  { repo: @org1_repo08, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo07, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo06, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo05, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo04, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo03, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo02, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo01, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                ]
                assert_equal "0", actual.previous
                assert_nil actual.next
              end

              test "it handles sorting" do
                sut = RepositoriesTableQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  sort_field: RepositoriesTableQuery::SortField::FIXED_WO_AUTOFIX,
                  sort_direction: RepositoriesTableQuery::SortDirection::ASC,
                )

                refute_nil actual
                assert_items @org, actual.items, [
                  { repo: @org1_repo01, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo02, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo03, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo04, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo05, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo06, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo07, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo08, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo09, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                  { repo: @org1_repo10, unresolved: 1, dismissed: 3, without_autofix: 1, with_autofix: 1 },
                ]
                assert_nil actual.previous
                assert_equal "10", actual.next
              end

              test "it applies tenant filtering" do
                org1 = create(:organization)
                org1.add_admin(@orgs_owner)
                org2 = create(:organization)
                org2.add_admin(@orgs_owner)

                # Create the repository under org2
                repository = create(:private_repository, owner: org2)

                # Create our version of repository with org1 - we're out of date
                repository_metadata = create(:soa_repository, repository:, organization: org1)

                create(:soa_feature_status_revision, repository_metadata:, date: @date, code_scanning_enabled: true)
                pull_request = create(:pull_request, :merged, :disable_disk_access, repository:, user: @orgs_owner)

                create(
                  :soa_code_scanning_pr_alert,
                  repository_metadata:,
                  pull_request_id: pull_request.id,
                  alert_number: 1,
                  date_id: @date.id,
                  alert_updated_at: @date.date_value.to_time,
                )

                sut = RepositoriesTableQuery.for_organization(
                  organization: org1,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  sort_field: RepositoriesTableQuery::SortField::UNRESOLVED,
                  sort_direction: RepositoriesTableQuery::SortDirection::DESC,
                )

                # Since the repository now belongs to org2, it
                # should have been filtered from these results
                refute_nil actual
                assert_empty actual.items
                assert_nil actual.previous
                assert_nil actual.next

                assert_dogstats_increment(1, "security_center.access_violation", tags: [
                  "feature:codeql-report",
                  "scope:organization",
                  "violation:repository_out_of_scope"
                ])
              end
            end
          end

          private

          sig do
            params(
              scope: T.any(::Business, ::Organization),
              items: T::Array[RepositoriesTableQuery::ListItem],
              expectations: T::Array[{ repo: ::Repository, unresolved: Integer, dismissed: Integer, without_autofix: Integer, with_autofix: Integer }],
            ).void
          end
          def assert_items(scope, items, expectations)
            refute_nil items
            refute_nil expectations
            assert_equal expectations.length, items.length

            expectations.each_with_index do |expectation, item_idx|
              refute_nil items[item_idx]
              item = T.must(items[item_idx])

              repo = T.let(expectation[:repo], ::Repository)
              expected_display_name = scope.is_a?(::Business) ? repo.name_with_display_owner : repo.name

              assert_equal repo.id.to_s, item.id, "Unexpected `id` value at index #{item_idx}"
              assert_equal expected_display_name, item.display_name, "Unexpected `display_name` value at index #{item_idx}"
              assert_equal UrlHelpers.repository_security_overview_path(repo.owner, repo), item.href, "Unexpected `href` value at index #{item_idx}"
              assert_equal expectation[:unresolved], item.count_unresolved, "Unexpected `count_unresolved` value at index #{item_idx}"
              assert_equal expectation[:dismissed], item.count_dismissed, "Unexpected `count_dismissed` value at index #{item_idx}"
              assert_equal expectation[:without_autofix], item.count_fixed_without_autofix, "Unexpected `count_fixed_without_autofix` value at index #{item_idx}"
              assert_equal expectation[:with_autofix], item.count_fixed_with_autofix, "Unexpected `count_fixed_with_autofix` value at index #{item_idx}"
            end
          end
        end
      end
    end
  end
end
