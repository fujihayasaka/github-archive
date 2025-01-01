# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      module Queries
        class DataExportQueryTest < GitHub::TestCase
          include DogstatsTestHelpers
          include DuplicateQueryTestHelper
          include SecurityCenter::TestFixtures
          include SecurityOverviewAnalytics::TestFixtures

          fixtures do
            create_business_level_fixtures

            date_id = 20240801
            @date = Date.find_by(id: date_id) || create(:soa_date, date_value: ::Date.parse(date_id.to_s))

            [
              @org1_private_repo = create(:private_repository, owner: @org),
              @org1_public_repo = create(:public_repository, owner: @org),
              @org2_private_repo = create(:private_repository, owner: @org2),
              @org2_public_repo = create(:public_repository, owner: @org2),
            ].each do |repository|
              repository_metadata = create(:soa_repository, repository:)
              create(:soa_feature_status_revision, repository_metadata:, date: @date, code_scanning_enabled: true)

              pull_request = create(:pull_request,
                :merged,
                :disable_disk_access,
                repository:,
                user: @orgs_owner,
              )

              create(
                :soa_code_scanning_pr_alert,
                repository_metadata:,
                pull_request_id: pull_request.id,
                alert_number: 1,
                date_id:,
                alert_updated_at: @date.date_value.to_time,
              )
              create(
                :soa_code_scanning_pr_alert,
                :fixed,
                repository_metadata:,
                pull_request_id: pull_request.id,
                alert_number: 2,
                date_id:,
                alert_updated_at: @date.date_value.to_time,
                has_autofix: true,
                autofix_accepted: true,
              )
              create(
                :soa_code_scanning_pr_alert,
                :resolved,
                repository_metadata:,
                pull_request_id: pull_request.id,
                alert_number: 3,
                date_id:,
                alert_updated_at: @date.date_value.to_time,
              )
            end

            create(:team, name: "users", organization: @org).tap do |team|
              team.add_repository(@org1_private_repo, :write)
              team.add_repository(@org1_public_repo, :write)
            end
            create(:team, name: "staff", organization: @org).tap do |team|
              team.add_repository(@org1_private_repo, :admin)
            end

            create(:topic, name: "apple").tap do |topic|
              create(:repository_topic, topic:, repository: @org1_public_repo)
              create(:repository_topic, topic:, repository: @org2_public_repo)
            end
            create(:topic, name: "banana").tap do |topic|
              create(:repository_topic, topic:, repository: @org1_public_repo)
              create(:repository_topic, topic:, repository: @org1_private_repo)
            end

            create(:custom_property_definition, :string, source: @org, property_name: "prop-string").tap do |definition|
              create(:custom_property_value, definition:, target: @org1_private_repo, value: "my value")
            end
            create(:custom_property_definition, :single_select, source: @org, property_name: "prop-single", allowed_values: %w[foo bar baz]).tap do |definition|
              create(:custom_property_value, definition:, target: @org1_public_repo, value: "foo")
            end
            create(:custom_property_definition, :true_false, source: @org, property_name: "prop-boolean").tap do |definition|
              create(:custom_property_value, definition:, target: @org1_private_repo, value: "true")
            end
            create(:custom_property_definition, :multi_select, source: @org2, property_name: "prop-multi", allowed_values: %w[one two three]).tap do |definition|
              create(:custom_property_value, definition:, target: @org2_public_repo, value: "one")
              create(:custom_property_value, definition:, target: @org2_public_repo, value: "two")
            end
          end

          setup do
            Timecop.freeze do
              @default_end_date = ::Date.parse("2024-08-14")
              @default_start_date = @default_end_date - 30.days
            end

            unresolved_alert_props = {
              alert_number: 1,
              severity: "critical",
              rule_sarif_identifier: "rb/unsafe-deserialization",
              created_at: (@date.date_value - 5.days).to_time,
              updated_at: (@date.date_value).to_time,
              resolved_at: nil,
              resolved_reason: nil,
              has_autofix: false,
              autofix_accepted: false,
            }
            fixed_alert_props = {
              alert_number: 2,
              severity: "critical",
              rule_sarif_identifier: "rb/unsafe-deserialization",
              created_at: (@date.date_value - 5.days).to_time,
              updated_at: @date.date_value.to_time,
              resolved_at: @date.date_value.to_time,
              resolved_reason: "fixed_or_revoked",
              has_autofix: true,
              autofix_accepted: true,
            }
            dismissed_alert_props = {
              alert_number: 3,
              severity: "critical",
              rule_sarif_identifier: "rb/unsafe-deserialization",
              created_at: (@date.date_value - 5.days).to_time,
              updated_at: @date.date_value.to_time,
              resolved_at: @date.date_value.to_time,
              resolved_reason: "risk_accepted",
              has_autofix: false,
              autofix_accepted: false,
            }

            org1_private_repo_pr = @org1_private_repo.pull_requests.first
            org1_private_repo_props = {
              repository_id: @org1_private_repo.id,
              repository_nwo: @org1_private_repo.name_with_display_owner,
              repository_visibility: @org1_private_repo.visibility,
              repository_archived: false,
              repository_teams: %w[staff users],
              repository_topics: %w[banana],
              repository_properties: {
                "prop-boolean" => "true",
                "prop-single" => nil,
                "prop-string" => "my value",
              },
              pull_request_id: org1_private_repo_pr.id,
              pull_request_number: org1_private_repo_pr.number,
              pull_request_url: org1_private_repo_pr.permalink,
            }
            org1_public_repo_pr = @org1_public_repo.pull_requests.first
            org1_public_repo_props = {
              repository_id: @org1_public_repo.id,
              repository_nwo: @org1_public_repo.name_with_display_owner,
              repository_visibility: @org1_public_repo.visibility,
              repository_archived: false,
              repository_teams: %w[users],
              repository_topics: %w[apple banana],
              repository_properties: {
                "prop-boolean" => nil,
                "prop-single" => "foo",
                "prop-string" => nil,
              },
              pull_request_id: org1_public_repo_pr.id,
              pull_request_number: org1_public_repo_pr.number,
              pull_request_url: org1_public_repo_pr.permalink,
            }
            org2_private_repo_pr = @org2_private_repo.pull_requests.first
            org2_private_repo_props = {
              repository_id: @org2_private_repo.id,
              repository_nwo: @org2_private_repo.name_with_display_owner,
              repository_visibility: @org2_private_repo.visibility,
              repository_archived: false,
              repository_teams: [],
              repository_topics: [],
              repository_properties: {
                "prop-multi" => nil,
              },
              pull_request_id: org2_private_repo_pr.id,
              pull_request_number: org2_private_repo_pr.number,
              pull_request_url: org2_private_repo_pr.permalink,
            }
            org2_public_repo_pr = @org2_public_repo.pull_requests.first
            org2_public_repo_props = {
              repository_id: @org2_public_repo.id,
              repository_nwo: @org2_public_repo.name_with_display_owner,
              repository_visibility: @org2_public_repo.visibility,
              repository_archived: false,
              repository_teams: [],
              repository_topics: %w[apple],
              repository_properties: {
                "prop-multi" => %w[one two],
              },
              pull_request_id: org2_public_repo_pr.id,
              pull_request_number: org2_public_repo_pr.number,
              pull_request_url: org2_public_repo_pr.permalink,
            }

            @org1_private_unresolved = DataExportQuery::ListItem.new(**org1_private_repo_props, **unresolved_alert_props)
            @org1_private_fixed = DataExportQuery::ListItem.new(**org1_private_repo_props, **fixed_alert_props)
            @org1_private_dismissed = DataExportQuery::ListItem.new(**org1_private_repo_props, **dismissed_alert_props)
            @org1_public_unresolved = DataExportQuery::ListItem.new(**org1_public_repo_props, **unresolved_alert_props)
            @org1_public_fixed = DataExportQuery::ListItem.new(**org1_public_repo_props, **fixed_alert_props)
            @org1_public_dismissed = DataExportQuery::ListItem.new(**org1_public_repo_props, **dismissed_alert_props)
            @org2_private_unresolved = DataExportQuery::ListItem.new(**org2_private_repo_props, **unresolved_alert_props)
            @org2_private_fixed = DataExportQuery::ListItem.new(**org2_private_repo_props, **fixed_alert_props)
            @org2_private_dismissed = DataExportQuery::ListItem.new(**org2_private_repo_props, **dismissed_alert_props)
            @org2_public_unresolved = DataExportQuery::ListItem.new(**org2_public_repo_props, **unresolved_alert_props)
            @org2_public_fixed = DataExportQuery::ListItem.new(**org2_public_repo_props, **fixed_alert_props)
            @org2_public_dismissed = DataExportQuery::ListItem.new(**org2_public_repo_props, **dismissed_alert_props)
          end

          context ".for_business" do
            context "#perform" do
              test "it works" do
                sut = DataExportQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = T.let(nil, T.nilable(DataExportQuery::Result))
                assert_duplicate_query_detection(DataExportQuery, 0) do
                  actual = sut.perform
                end

                refute_nil actual
                assert_equal 12, actual&.items&.length
                assert_equal [
                  @org1_private_unresolved,
                  @org1_private_fixed,
                  @org1_private_dismissed,
                  @org1_public_unresolved,
                  @org1_public_fixed,
                  @org1_public_dismissed,
                  @org2_private_unresolved,
                  @org2_private_fixed,
                  @org2_private_dismissed,
                  @org2_public_unresolved,
                  @org2_public_fixed,
                  @org2_public_dismissed,
                ].map(&:serialize), actual&.items&.map(&:serialize)
                assert_nil actual&.next
              end

              test "it filters to authorized organizations" do
                sut = DataExportQuery.for_business(
                  business: @business,
                  organizations: [@org],
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 6, actual.items.length
                assert_equal [
                  @org1_private_unresolved,
                  @org1_private_fixed,
                  @org1_private_dismissed,
                  @org1_public_unresolved,
                  @org1_public_fixed,
                  @org1_public_dismissed,
                ].map(&:serialize), actual.items.map(&:serialize)
                assert_nil actual.next
              end

              test "it returns no data when no authorized organizations" do
                sut = DataExportQuery.for_business(
                  business: @business,
                  organizations: [],
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_empty actual.items
                assert_nil actual.next
              end

              test "it applies repo filters" do
                sut = DataExportQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("visibility:private"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 6, actual.items.length
                assert_equal [
                  @org1_private_unresolved,
                  @org1_private_fixed,
                  @org1_private_dismissed,
                  @org2_private_unresolved,
                  @org2_private_fixed,
                  @org2_private_dismissed,
                ].map(&:serialize), actual.items.map(&:serialize)
                assert_nil actual.next
              end

              test "it applies alert filters" do
                sut = DataExportQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("codeql.autofix:accepted"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                assert_equal 4, actual.items.length
                assert_equal [
                  @org1_private_fixed,
                  @org1_public_fixed,
                  @org2_private_fixed,
                  @org2_public_fixed,
                ].map(&:serialize), actual.items.map(&:serialize)
                assert_nil actual.next
              end

              test "it handles pagination" do
                sut = DataExportQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                DataExportQuery.stub_const(:PAGE_SIZE, 5) do
                  actual = sut.perform(cursor: nil)

                  refute_nil actual
                  assert_equal 5, actual.items.length
                  assert_equal [
                    @org1_private_unresolved,
                    @org1_private_fixed,
                    @org1_private_dismissed,
                    @org1_public_unresolved,
                    @org1_public_fixed,
                  ].map(&:serialize), actual.items.map(&:serialize)
                  refute_nil actual.next

                  actual = sut.perform(cursor: actual.next)

                  refute_nil actual
                  assert_equal 5, actual.items.length
                  assert_equal [
                    @org1_public_dismissed,
                    @org2_private_unresolved,
                    @org2_private_fixed,
                    @org2_private_dismissed,
                    @org2_public_unresolved,
                  ].map(&:serialize), actual.items.map(&:serialize)
                  refute_nil actual.next

                  actual = sut.perform(cursor: actual.next)

                  refute_nil actual
                  assert_equal 2, actual.items.length
                  assert_equal [
                    @org2_public_fixed,
                    @org2_public_dismissed,
                  ].map(&:serialize), actual.items.map(&:serialize)
                  assert_nil actual.next
                end
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

                sut = DataExportQuery.for_business(
                  business: biz1,
                  organizations: [org1],
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                # Since the repository now belongs to org2, it
                # should have been filtered from these results
                refute_nil actual
                assert_empty actual.items
                assert_nil actual.next

                assert_dogstats_increment(1, "security_center.access_violation", tags: [
                  "feature:codeql-report-export",
                  "scope:business",
                  "violation:repository_out_of_scope"
                ])
              end
            end
          end

          context ".for_organization" do
            context "#perform" do
              test "it works" do
                sut = DataExportQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = T.let(nil, T.nilable(DataExportQuery::Result))
                assert_duplicate_query_detection(DataExportQuery, 0) do
                  actual = sut.perform
                end

                refute_nil actual
                assert_equal 6, actual&.items&.length
                assert_equal [
                  @org1_private_unresolved,
                  @org1_private_fixed,
                  @org1_private_dismissed,
                  @org1_public_unresolved,
                  @org1_public_fixed,
                  @org1_public_dismissed,
                ].map(&:serialize), actual&.items&.map(&:serialize)
                assert_nil actual&.next
              end

              test "it filters to accessible repositories" do
                sut = DataExportQuery.for_organization(
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
                assert_equal 3, actual.items.length
                assert_equal [
                  @org1_private_unresolved,
                  @org1_private_fixed,
                  @org1_private_dismissed,
                ].map(&:serialize), actual.items.map(&:serialize)
                assert_nil actual.next
              end

              test "it returns no data when no accessible repositories" do
                sut = DataExportQuery.for_organization(
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
                assert_empty actual.items
                assert_nil actual.next
              end

              test "it applies repo filters" do
                sut = DataExportQuery.for_organization(
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
                assert_equal 3, actual.items.length
                assert_equal [
                  @org1_private_unresolved,
                  @org1_private_fixed,
                  @org1_private_dismissed,
                ].map(&:serialize), actual.items.map(&:serialize)
                assert_nil actual.next
              end

              test "it applies alert filters" do
                sut = DataExportQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new("codeql.autofix:accepted"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                refute_nil actual
                refute_nil actual.items
                assert_equal 2, actual.items.length
                assert_equal [
                  @org1_private_fixed,
                  @org1_public_fixed,
                ].map(&:serialize), actual.items.map(&:serialize)
                assert_nil actual.next
              end

              test "it handles pagination" do
                sut = DataExportQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                DataExportQuery.stub_const(:PAGE_SIZE, 5) do
                  actual = sut.perform(cursor: nil)

                  refute_nil actual
                  assert_equal 5, actual.items.length
                  assert_equal [
                    @org1_private_unresolved,
                    @org1_private_fixed,
                    @org1_private_dismissed,
                    @org1_public_unresolved,
                    @org1_public_fixed,
                  ].map(&:serialize), actual.items.map(&:serialize)
                  refute_nil actual.next

                  actual = sut.perform(cursor: actual.next)

                  refute_nil actual
                  assert_equal 1, actual.items.length
                  assert_equal [
                    @org1_public_dismissed,
                  ].map(&:serialize), actual.items.map(&:serialize)
                  assert_nil actual.next
                end
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

                sut = DataExportQuery.for_organization(
                  organization: org1,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform

                # Since the repository now belongs to org2, it
                # should have been filtered from these results
                refute_nil actual
                assert_empty actual.items
                assert_nil actual.next

                assert_dogstats_increment(1, "security_center.access_violation", tags: [
                  "feature:codeql-report-export",
                  "scope:organization",
                  "violation:repository_out_of_scope"
                ])
              end
            end
          end
        end
      end
    end
  end
end
