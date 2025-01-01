# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    class ByRepositoryTest < GitHub::TestCase
      fixtures do
        @org = create(:organization, name: "test-org")

        @repo_a = create_repo("#{@org}-repo-a", owner: @org)
        @repo_b = create_repo("#{@org}-repo-b", owner: @org)
        @repo_c = create_repo("#{@org}-repo-c", owner: @org)
      end

      setup do
        @base_rel = Repository.all
      end

      context "#apply" do
        context "substring matching" do
          test "filters by partial repository name" do
            filter = ByRepository.new([], [], substring_match: true)
            expected_repos = [@repo_a, @repo_b, @repo_c]
            assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

            filter = ByRepository.new(["unknown"], [], substring_match: true)
            assert_empty filter.apply(@base_rel).map(&:repository_id)

            filter = ByRepository.new([@repo_a.name], [], substring_match: true)
            expected_repos = [@repo_a]
            assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

            filter = ByRepository.new(["repo-a"], [], substring_match: true)
            expected_repos = [@repo_a]
            assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

            filter = ByRepository.new(["repo"], [], substring_match: true)
            expected_repos = [@repo_a, @repo_b, @repo_c]
            assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

            filter = ByRepository.new([], ["unknown"], substring_match: true)
            expected_repos = [@repo_a, @repo_b, @repo_c]
            assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

            filter = ByRepository.new([], [@repo_a.name], substring_match: true)
            expected_repos = [@repo_b, @repo_c]
            assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

            filter = ByRepository.new([], ["repo-a"], substring_match: true)
            expected_repos = [@repo_b, @repo_c]
            assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

            filter = ByRepository.new([], ["repo"], substring_match: true)
            assert_empty filter.apply(@base_rel).map(&:repository_id)
          end
        end

        test "filters by repository name" do
          filter = ByRepository.new([], [])
          expected_repos = [@repo_a, @repo_b, @repo_c]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByRepository.new([@repo_a.name], [])
          expected_repos = [@repo_a]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByRepository.new([@repo_b.name], [])
          expected_repos = [@repo_b]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByRepository.new([], [@repo_a.name])
          expected_repos = [@repo_b, @repo_c]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByRepository.new([], [@repo_b.name])
          expected_repos = [@repo_a, @repo_c]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByRepository.new(["unknown"], [])
          assert_empty filter.apply(@base_rel).map(&:repository_id)

          filter = ByRepository.new([], ["unknown"])
          expected_repos = [@repo_a, @repo_b, @repo_c]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)
        end

        test "doesn't apply clause if no filters are provided" do
          expected_clause = @base_rel.to_sql

          filter = ByRepository.new([], [])
          assert_equal expected_clause, filter.apply(@base_rel).to_sql
        end

        test "applies where clause with positive filters" do
          prefix_sql = @base_rel.to_sql

          filter = ByRepository.new([@repo_a.name], [])
          expected_clause = "WHERE `soa_repositories`.`name` = '#{@repo_a.name}'"
          assert_equal expected_clause, filter.apply(@base_rel).to_sql.delete_prefix(prefix_sql).strip
        end

        test "applies where clause with negated filters" do
          prefix_sql = @base_rel.to_sql

          filter = ByRepository.new([], [@repo_a.name])
          expected_clause = "WHERE `soa_repositories`.`name` != '#{@repo_a.name}'"
          assert_equal expected_clause, filter.apply(@base_rel).to_sql.delete_prefix(prefix_sql).strip
        end
      end

      context "#is_empty?" do
        test "returns 'true' when provided no filters" do
          assert ByRepository.new([], []).is_empty?
        end

        test "returns 'false' when provided inclusive filters" do
          refute ByRepository.new(["test"], []).is_empty?
        end

        test "returns 'false' when provided exclusive filters" do
          refute ByRepository.new([], ["test"]).is_empty?
        end

        test "returns 'false' when provided both inclusive and exclusive filters" do
          refute ByRepository.new(["test"], ["test2"]).is_empty?
        end
      end

      context "#has_incl_filters?" do
        test "returns 'false' when provided no filters" do
          refute ByRepository.new([], []).has_incl_filters?
        end

        test "returns 'true' when provided inclusive filters" do
          assert ByRepository.new(["test"], []).has_incl_filters?
        end

        test "returns 'false' when provided exclusive filters" do
          refute ByRepository.new([], ["test"]).has_incl_filters?
        end

        test "returns 'true' when provided both inclusive and exclusive filters" do
          assert ByRepository.new(["test"], ["test2"]).has_incl_filters?
        end
      end

      def create_repo(name, owner:)
        create(:repository, name: name, owner: owner).tap do |r|
          create(:security_overview_analytics_repository, repository: r)
        end
      end
    end
  end
end
