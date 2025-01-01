# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    class ByVisibilityTest < GitHub::TestCase
      fixtures do
        GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
        business = create(:global_business)
        @org = create(:organization, business: business)

        @repo_public = create_repo("#{@org}-public-repo", owner: @org, visibility: :public)
        @repo_internal = create_repo("#{@org}-not-internal-repo", owner: @org, visibility: :internal)
        @repo_private = create_repo("#{@org}-private-repo", owner: @org, visibility: :private)
      end

      setup do
        @base_rel = Repository.all
      end

      context "#apply" do
        test "filters by repository visibility" do
          filter = ByVisibility.new([], [])
          expected_repos = [@repo_public, @repo_internal, @repo_private]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByVisibility.new(["public"], [])
          expected_repos = [@repo_public]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByVisibility.new(["internal"], [])
          expected_repos = [@repo_internal]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByVisibility.new(["private"], [])
          expected_repos = [@repo_private]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByVisibility.new(%w[public private], [])
          expected_repos = [@repo_public, @repo_private]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByVisibility.new([], ["public"])
          expected_repos = [@repo_internal, @repo_private]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByVisibility.new([], ["internal"])
          expected_repos = [@repo_public, @repo_private]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByVisibility.new([], ["private"])
          expected_repos = [@repo_public, @repo_internal]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByVisibility.new([], %w[public private])
          expected_repos = [@repo_internal]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)
        end

        test "doesn't apply clause if no filters are provided" do
          expected_clause = @base_rel.to_sql

          filter = ByVisibility.new(nil, nil)
          assert_equal expected_clause, filter.apply(@base_rel).to_sql

          filter = ByVisibility.new([], [])
          assert_equal expected_clause, filter.apply(@base_rel).to_sql
        end

        test "returns null relation if only invalid positive filters are provided" do
          expected_clause = @base_rel.to_sql

          filter = ByVisibility.new(["visible"], [])
          assert filter.apply(@base_rel).null_relation?

          filter = ByVisibility.new(%w[public visible], [])
          refute filter.apply(@base_rel).null_relation?
        end

        test "doesn't apply clause if any invalid negated filters are provided" do
          expected_clause = @base_rel.to_sql

          filter = ByVisibility.new([], ["visible"])
          assert_equal expected_clause, filter.apply(@base_rel).to_sql

          filter = ByVisibility.new([], %w[public visible])
          assert_equal expected_clause, filter.apply(@base_rel).to_sql
        end

        test "applies where clause with positive filters" do
          prefix_sql = @base_rel.to_sql

          filter = ByVisibility.new(["public"], [])
          expected_clause = "WHERE `soa_repositories`.`visibility` = 0"
          assert_equal expected_clause, filter.apply(@base_rel).to_sql.delete_prefix(prefix_sql).strip

          filter = ByVisibility.new(["private"], [])
          expected_clause = "WHERE `soa_repositories`.`visibility` = 1"
          assert_equal expected_clause, filter.apply(@base_rel).to_sql.delete_prefix(prefix_sql).strip
        end

        test "applies where clause with negated filters" do
          prefix_sql = @base_rel.to_sql

          filter = ByVisibility.new([], ["public"])
          expected_clause = "WHERE `soa_repositories`.`visibility` != 0"
          assert_equal expected_clause, filter.apply(@base_rel).to_sql.delete_prefix(prefix_sql).strip

          filter = ByVisibility.new([], ["private"])
          expected_clause = "WHERE `soa_repositories`.`visibility` != 1"
          assert_equal expected_clause, filter.apply(@base_rel).to_sql.delete_prefix(prefix_sql).strip
        end

        test "applies where clause with case-insensitivity for filters" do
          prefix_sql = @base_rel.to_sql

          filter = ByVisibility.new(["Public"], ["INTERNAL"])
          expected_clause = "WHERE `soa_repositories`.`visibility` = 0 AND `soa_repositories`.`visibility` != 2"
          assert_equal expected_clause, filter.apply(@base_rel).to_sql.delete_prefix(prefix_sql).strip
        end
      end

      context "#is_empty?" do
        test "returns proper result for is_empty?" do
          assert ByVisibility.new(nil, nil).is_empty?
          assert ByVisibility.new([], []).is_empty?
          refute ByVisibility.new(["private"], []).is_empty?
          refute ByVisibility.new([], ["private"]).is_empty?
          refute ByVisibility.new(["public"], ["private"]).is_empty?
        end
      end

      context "#has_incl_filters?" do
        test "returns proper result for has_incl_filters?" do
          refute ByVisibility.new(nil, nil).has_incl_filters?
          refute ByVisibility.new([], []).has_incl_filters?
          assert ByVisibility.new(["private"], []).has_incl_filters?
          refute ByVisibility.new([], ["private"]).has_incl_filters?
          assert ByVisibility.new(["public"], ["private"]).has_incl_filters?
        end
      end

      def create_repo(name, owner:, visibility: :private)
        factory = if visibility == :private
          :private_repository
        elsif visibility == :public
          :repository
        elsif visibility == :internal
          :internal_repository
        end

        create(factory, name: name, owner: owner).tap do |r|
          create(:security_overview_analytics_repository, repository: r)
        end
      end
    end
  end
end
