# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    module FeatureStatusSummary
      class SortByTest < GitHub::TestCase
        fixtures do
          now = Time.now

          @org = create(:organization)
          @page_size = 25

          @repo1 = create(:soa_repository, name: "repo-a", pushed_at: now - 2.days).tap do |repository_metadata|
            create(
              :soa_feature_status,
              repository_metadata:,
              advanced_security_status: "ENABLED",
              dependabot_alerts_status: "ENABLED",
              dependabot_alerts_total_count: 1,
              code_scanning_alerts_status: "ENABLED",
              code_scanning_alerts_total_count: 2,
              secret_scanning_alerts_status: "ENABLED",
              secret_scanning_alerts_total_count: 3,
            )
          end

          @repo2 = create(:soa_repository, name: "repo-b", pushed_at: now - 1.day).tap do |repository_metadata|
            create(
              :soa_feature_status,
              repository_metadata:,
              advanced_security_status: "ENABLED",
              dependabot_alerts_status: "ENABLED",
              dependabot_alerts_total_count: 3,
              code_scanning_alerts_status: "ENABLED",
              code_scanning_alerts_total_count: 3,
              secret_scanning_alerts_status: "ENABLED",
              secret_scanning_alerts_total_count: 1,
            )
          end

          @repo3 = create(:soa_repository, name: "repo-c", pushed_at: now).tap do |repository_metadata|
            create(
              :soa_feature_status,
              repository_metadata:,
              advanced_security_status: "ENABLED",
              dependabot_alerts_status: "ENABLED",
              dependabot_alerts_total_count: 2,
              code_scanning_alerts_status: "ENABLED",
              code_scanning_alerts_total_count: 1,
              secret_scanning_alerts_status: "ENABLED",
              secret_scanning_alerts_total_count: 2,
            )
          end
        end

        setup do
          @rel = Repository.joins(:feature_status_summary).all
        end

        context "#apply" do
          test "orders by repository pushed_at desc by default" do
            rel_with_sort = SortBy.new(nil).apply(@rel)
            assert_equal [@repo3, @repo2, @repo1].map(&:name), rel_with_sort.map(&:name)

            expected_clause = Arel.sql("`#{Repository.table_name}`.`pushed_at` DESC, `#{Repository.table_name}`.`name` ASC")
            assert rel_with_sort.to_sql.include?(expected_clause)
          end

          test "orders by repository pushed_at desc by default if option is not supported" do
            rel_with_sort = SortBy.new("woooooof").apply(@rel)
            assert_equal [@repo3, @repo2, @repo1].map(&:name), rel_with_sort.map(&:name)

            expected_clause = Arel.sql("`#{Repository.table_name}`.`pushed_at` DESC, `#{Repository.table_name}`.`name` ASC")
            assert rel_with_sort.to_sql.include?(expected_clause)
          end

          test "orders by repository pushed_at desc if option set to last-updated" do
            rel_with_sort = SortBy.new("last-updated").apply(@rel)
            assert_equal [@repo3, @repo2, @repo1].map(&:name), rel_with_sort.map(&:name)
          end

          test "orders by repository name asc if option set to repos" do
            rel_with_sort = SortBy.new("repos").apply(@rel)
            assert_equal [@repo1, @repo2, @repo3].map(&:name), rel_with_sort.map(&:name)
          end

          test "orders by dependabot alerts count desc if option set to dependabot" do
            rel_with_sort = SortBy.new("dependabot").apply(@rel)
            assert_equal [@repo2, @repo3, @repo1].map(&:name), rel_with_sort.map(&:name)
          end

          test "orders by code scanning alerts count desc if option set to code-scanning" do
            rel_with_sort = SortBy.new("code-scanning").apply(@rel)
            assert_equal [@repo2, @repo1, @repo3].map(&:name), rel_with_sort.map(&:name)
          end

          test "orders by secret scanning alerts count desc if option set to secret-scanning" do
            rel_with_sort = SortBy.new("secret-scanning").apply(@rel)
            assert_equal [@repo1, @repo3, @repo2].map(&:name), rel_with_sort.map(&:name)
          end
        end

        context ".sort_option_or_default" do
          test "returns provided option if valid" do
            assert_equal :"last-updated", SortBy.sort_option_or_default("last-updated")
            assert_equal :repos, SortBy.sort_option_or_default("repos")
            assert_equal :dependabot, SortBy.sort_option_or_default("dependabot")
            assert_equal :"code-scanning", SortBy.sort_option_or_default("code-scanning")
            assert_equal :"secret-scanning", SortBy.sort_option_or_default("secret-scanning")
          end

          test "returns default option if nil" do
            assert_equal :"last-updated", SortBy.sort_option_or_default(nil)
          end

          test "returns provided option if in allowlist" do
            assert_equal :foo, SortBy.sort_option_or_default("foo", valid_options: [:foo, :bar])

            assert_equal :"last-updated", SortBy.sort_option_or_default("last-updated", valid_options: SortBy::COVERAGE_SORT_OPTIONS)
            assert_equal :repos, SortBy.sort_option_or_default("repos", valid_options: SortBy::COVERAGE_SORT_OPTIONS)

            assert_equal :"last-updated", SortBy.sort_option_or_default("last-updated", valid_options: SortBy::RISK_SORT_OPTIONS)
            assert_equal :repos, SortBy.sort_option_or_default("repos", valid_options: SortBy::RISK_SORT_OPTIONS)
            assert_equal :dependabot, SortBy.sort_option_or_default("dependabot", valid_options: SortBy::RISK_SORT_OPTIONS)
            assert_equal :"code-scanning", SortBy.sort_option_or_default("code-scanning", valid_options: SortBy::RISK_SORT_OPTIONS)
            assert_equal :"secret-scanning", SortBy.sort_option_or_default("secret-scanning", valid_options: SortBy::RISK_SORT_OPTIONS)
          end

          test "returns default option if not in allowlist" do
            assert_equal :"last-updated", SortBy.sort_option_or_default("foo", valid_options: [])
            assert_equal :"last-updated", SortBy.sort_option_or_default("dependabot", valid_options: [:foo, :bar])
            assert_equal :"last-updated", SortBy.sort_option_or_default("dependabot", valid_options: SortBy::COVERAGE_SORT_OPTIONS)
            assert_equal :"last-updated", SortBy.sort_option_or_default("code-scanning", valid_options: SortBy::COVERAGE_SORT_OPTIONS)
            assert_equal :"last-updated", SortBy.sort_option_or_default("secret-scanning", valid_options: SortBy::COVERAGE_SORT_OPTIONS)
          end
        end
      end
    end
  end
end
