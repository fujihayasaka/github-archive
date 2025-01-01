# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    class ByArchivedTest < GitHub::TestCase
      fixtures do
        @org = create(:organization)
        @repo_archived = create_repo("#{@org}-archived-repo", owner: @org, archived: true)
        @repo_not_archived = create_repo("#{@org}-not-archived-repo", owner: @org)
      end

      setup do
        @base_rel = Repository.all
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

      context "#has_incl_filters?" do
        test "returns 'false' when provided no filters" do
          refute ByArchived.new([], []).has_incl_filters?
        end

        test "returns 'true' when provided inclusive filters" do
          assert ByArchived.new(["true"], []).has_incl_filters?
          assert ByArchived.new(["false"], []).has_incl_filters?
        end

        test "returns 'false' when provided exclusive filters" do
          refute ByArchived.new([], ["true"]).has_incl_filters?
          refute ByArchived.new([], ["false"]).has_incl_filters?
        end

        test "returns 'true' when provided both inclusive and exclusive filters" do
          assert ByArchived.new(["true"], ["true"]).has_incl_filters?
          assert ByArchived.new(["true"], ["false"]).has_incl_filters?
          assert ByArchived.new(["false"], ["true"]).has_incl_filters?
          assert ByArchived.new(["false"], ["false"]).has_incl_filters?
        end
      end

      def create_repo(name, owner:, archived: false)
        create(:repository, name: name, owner: owner).tap do |r|
          r.set_archived if archived
          create(:security_overview_analytics_repository, repository: r)
        end
      end
    end
  end
end
