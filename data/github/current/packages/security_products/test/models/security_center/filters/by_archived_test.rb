# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Filters
    class ByArchivedTest < GitHub::TestCase
      fixtures do
        @org = create(:organization)

        @repo_archived = create_repo("#{@org}-archived-repo", owner: @org, archived: true)
        @repo_not_archived = create_repo("#{@org}-not-archived-repo", owner: @org, archived: false)
      end

      setup do
        @base_rel = RepositorySecurityCenterConfig.all.left_outer_joins(:repository_security_center_statuses).group(:repository_id)
      end

      context "#apply" do
        context "no filters are provided" do
          test "does not filter on repositories" do
            assert_query_count(1) do
              ByArchived.new([], []).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_archived.id, @repo_not_archived.id]
              assert_same_elements expected, repo_ids
            end
          end
        end

        context "inclusive filters" do
          test "filters by archived state" do
            assert_query_count(1) do
              ByArchived.new(["true"], []).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_archived.id]
              assert_same_elements expected, repo_ids
            end

            assert_query_count(1) do
              ByArchived.new(["false"], []).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_not_archived.id]
              assert_same_elements expected, repo_ids
            end
          end

          test "filters by OR'd archived states with multiple filter values" do
            assert_query_count(1) do
              ByArchived.new(%w[true false], []).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_archived.id, @repo_not_archived.id]
              assert_same_elements expected, repo_ids
            end
          end

          test "filters by archived state with repeated non-conflicting filter values" do
            assert_query_count(1) do
              ByArchived.new(%w[true true true], []).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_archived.id]
              assert_same_elements expected, repo_ids
            end

            assert_query_count(1) do
              ByArchived.new(%w[false false false], []).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_not_archived.id]
              assert_same_elements expected, repo_ids
            end
          end
        end

        context "exclusive filters" do
          test "filters by archived state" do
            assert_query_count(1) do
              ByArchived.new([], ["true"]).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_not_archived.id]
              assert_same_elements expected, repo_ids
            end

            assert_query_count(1) do
              ByArchived.new([], ["false"]).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_archived.id]
              assert_same_elements expected, repo_ids
            end
          end

          test "filters by AND'd archived states with multiple filter values" do
            assert_query_count(1) do
              ByArchived.new([], %w[true false]).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              assert_empty repo_ids
            end
          end

          test "filters by archived state with repeated non-conflicting filter values" do
            assert_query_count(1) do
              ByArchived.new([], %w[true true true]).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_not_archived.id]
              assert_same_elements expected, repo_ids
            end

            assert_query_count(1) do
              ByArchived.new([], %w[false false false]).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_archived.id]
              assert_same_elements expected, repo_ids
            end
          end
        end

        context "inclusive and exclusive filters" do
          test "filters by archived state" do
            assert_query_count(1) do
              ByArchived.new(["true"], ["false"]).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_archived.id]
              assert_same_elements expected, repo_ids
            end

            assert_query_count(1) do
              ByArchived.new(["false"], ["true"]).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_not_archived.id]
              assert_same_elements expected, repo_ids
            end
          end

          test "filters by OR'd inclusive archived states and AND'd exclusive archived states" do
            assert_query_count(1) do
              ByArchived.new(%w[true false], ["false"]).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_archived.id]
              assert_same_elements expected, repo_ids
            end

            assert_query_count(1) do
              ByArchived.new(["true"], %w[true false]).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              assert_empty repo_ids
            end
          end

          test "filters by archived state with repeated non-conflicting filter values" do
            assert_query_count(1) do
              ByArchived.new(%w[true true], %w[false false]).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_archived.id]
              assert_same_elements expected, repo_ids
            end

            assert_query_count(1) do
              ByArchived.new(%w[false false], %w[true true]).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_not_archived.id]
              assert_same_elements expected, repo_ids
            end
          end

          test "returns no results for conflicting filter values" do
            assert_query_count(1) do
              ByArchived.new(["true"], ["true"]).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              assert_empty repo_ids
            end

            assert_query_count(1) do
              ByArchived.new(["false"], ["false"]).apply(@base_rel).map(&:repository_id)
            end.tap do |repo_ids|
              assert_empty repo_ids
            end
          end
        end

        context "applied multiple times" do
          test "filters as expected when same filter values are applied multiple times" do
            assert_query_count(1) do
              rel = @base_rel
              3.times { rel = ByArchived.new(["true"], []).apply(rel) }
              rel.map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_archived.id]
              assert_same_elements expected, repo_ids
            end

            assert_query_count(1) do
              rel = @base_rel
              3.times { rel = ByArchived.new([], ["true"]).apply(rel) }
              rel.map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_not_archived.id]
              assert_same_elements expected, repo_ids
            end
          end

          test "filters as expected when different filter values are applied" do
            assert_query_count(1) do
              @base_rel \
                .then { |rel| ByArchived.new(["true"], []).apply(rel) }
                .then { |rel| ByArchived.new([], ["false"]).apply(rel) }
                .map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_archived.id]
              assert_same_elements expected, repo_ids
            end

            assert_query_count(1) do
              @base_rel \
                .then { |rel| ByArchived.new(["false"], []).apply(rel) }
                .then { |rel| ByArchived.new([], ["true"]).apply(rel) }
                .map(&:repository_id)
            end.tap do |repo_ids|
              expected = [@repo_not_archived.id]
              assert_same_elements expected, repo_ids
            end
          end

          test "returns no results when conflicting filter values are applied" do
            assert_query_count(1) do
              @base_rel \
                .then { |rel| ByArchived.new(["true"], []).apply(rel) }
                .then { |rel| ByArchived.new([], ["true"]).apply(rel) }
                .map(&:repository_id)
            end.tap do |repo_ids|
              assert_empty repo_ids
            end

            assert_query_count(1) do
              @base_rel \
                .then { |rel| ByArchived.new(["false"], []).apply(rel) }
                .then { |rel| ByArchived.new([], ["false"]).apply(rel) }
                .map(&:repository_id)
            end.tap do |repo_ids|
              assert_empty repo_ids
            end
          end
        end
      end

      context "#is_empty?" do
        test "returns 'true' when provided no filters" do
          assert ByArchived.new([], []).is_empty?
        end

        test "returns 'false' when provided inclusive filters" do
          refute ByArchived.new(["true"], []).is_empty?
          refute ByArchived.new(["false"], []).is_empty?
        end

        test "returns 'false' when provided exclusive filters" do
          refute ByArchived.new([], ["true"]).is_empty?
          refute ByArchived.new([], ["false"]).is_empty?
        end

        test "returns 'false' when provided both inclusive and exclusive filters" do
          refute ByArchived.new(["true"], ["true"]).is_empty?
          refute ByArchived.new(["true"], ["false"]).is_empty?
          refute ByArchived.new(["false"], ["true"]).is_empty?
          refute ByArchived.new(["false"], ["false"]).is_empty?
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
