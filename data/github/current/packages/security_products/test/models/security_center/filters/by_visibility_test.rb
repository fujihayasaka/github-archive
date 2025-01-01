# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
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

      context "#apply" do
        test "filters by repository visibility" do
          rel = RepositorySecurityCenterConfig.all.left_outer_joins(:repository_security_center_statuses).group(:repository_id)

          filter = ByVisibility.new([], [])
          expected_repos = [@repo_public, @repo_internal, @repo_private]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByVisibility.new(["public"], [])
          expected_repos = [@repo_public]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByVisibility.new(["internal"], [])
          expected_repos = [@repo_internal]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByVisibility.new(["private"], [])
          expected_repos = [@repo_private]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByVisibility.new(%w[public private], [])
          expected_repos = [@repo_public, @repo_private]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByVisibility.new([], ["public"])
          expected_repos = [@repo_internal, @repo_private]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByVisibility.new([], ["internal"])
          expected_repos = [@repo_public, @repo_private]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByVisibility.new([], ["private"])
          expected_repos = [@repo_public, @repo_internal]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByVisibility.new([], %w[public private])
          expected_repos = [@repo_internal]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)
        end

        test "doesn't apply clause if no filters are provided" do
          rel = RepositorySecurityCenterConfig.all
          expected_clause = rel.to_sql

          filter = ByVisibility.new(nil, nil)
          assert_equal expected_clause, filter.apply(rel).to_sql

          filter = ByVisibility.new([], [])
          assert_equal expected_clause, filter.apply(rel).to_sql
        end

        test "returns proper result for is_empty?" do
          assert ByVisibility.new(nil, nil).is_empty?
          assert ByVisibility.new([], []).is_empty?
          refute ByVisibility.new(["private"], []).is_empty?
          refute ByVisibility.new([], ["private"]).is_empty?
        end

        test "returns null relation if only invalid positive filters are provided" do
          rel = RepositorySecurityCenterConfig.all
          expected_clause = rel.to_sql

          filter = ByVisibility.new(["visible"], [])
          assert filter.apply(rel).null_relation?

          filter = ByVisibility.new(%w[public visible], [])
          refute filter.apply(rel).null_relation?
        end

        test "doesn't apply clause if any invalid negated filters are provided" do
          rel = RepositorySecurityCenterConfig.all
          expected_clause = rel.to_sql

          filter = ByVisibility.new([], ["visible"])
          assert_equal expected_clause, filter.apply(rel).to_sql

          filter = ByVisibility.new([], %w[public visible])
          assert_equal expected_clause, filter.apply(rel).to_sql
        end

        test "applies where clause with positive filters" do
          rel = RepositorySecurityCenterConfig.all
          prefix_sql = rel.to_sql

          filter = ByVisibility.new(["public"], [])
          expected_clause = "WHERE `repository_security_center_configs`.`visibility` = 'public'"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip

          filter = ByVisibility.new(["private"], [])
          expected_clause = "WHERE `repository_security_center_configs`.`visibility` = 'private'"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
        end

        test "applies where clause with negated filters" do
          rel = RepositorySecurityCenterConfig.all
          prefix_sql = rel.to_sql

          filter = ByVisibility.new([], ["public"])
          expected_clause = "WHERE `repository_security_center_configs`.`visibility` != 'public'"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip

          filter = ByVisibility.new([], ["private"])
          expected_clause = "WHERE `repository_security_center_configs`.`visibility` != 'private'"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
        end

        test "applies where clause with case-insensitivity for filters" do
          rel = RepositorySecurityCenterConfig.all
          prefix_sql = rel.to_sql

          filter = ByVisibility.new(["Public"], ["INTERNAL"])
          expected_clause = "WHERE `repository_security_center_configs`.`visibility` = 'public' AND `repository_security_center_configs`.`visibility` != 'internal'"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
        end
      end

      def create_repo(name, owner:, visibility: :private, archived: false, enabled_features: [], not_enabled_features: [], create_not_enabled_statuses_for_unspecified_features: true)
        factory = if visibility == :private
          :private_repository
        elsif visibility == :public
          :repository
        elsif visibility == :internal
          :internal_repository
        end

        create(factory, name: name, owner: owner).tap do |r|
          r.set_archived if archived

          create(
            :repository_security_center_config,
            repository: r,
            ghas_enabled: true,
          )

          all_feature_types = RepositorySecurityCenterStatus.primary_feature_types.flat_map do |primary_type|
            [primary_type] + RepositorySecurityCenterStatus.subfeatures_for(primary_type)
          end

          enabled_features.each do |feature|
            raise "Unknown feature type #{feature}" unless all_feature_types.include?(feature)
            create_status(r, feature: feature, enrolled: true)
          end

          not_enabled_features.each do |feature|
            raise "Unknown feature type #{feature}" unless all_feature_types.include?(feature)
            create_status(r, feature: feature, enrolled: false)
          end

          if create_not_enabled_statuses_for_unspecified_features
            (all_feature_types - enabled_features - not_enabled_features).each do |feature|
              create_status(r, feature: feature, enrolled: false)
            end
          end
        end
      end

      def create_status(repo, feature:, enrolled:)
        create(
          :repository_security_center_status,
          feature,
          enrolled ? :enrolled : :not_enrolled,
          repository: repo,
        )
      end
    end
  end
end
