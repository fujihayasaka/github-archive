# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Filters
    class ByGhasTest < GitHub::TestCase
      fixtures do
        @org = create(:organization)

        @ghas_repos = [
          (@repo_cs_enabled = create_repo("#{@org}-cs-enabled-repo", owner: @org)),
          (@repo_ss_enabled = create_repo("#{@org}-ss-enabled-repo", owner: @org)),
          (@repo_cs_ss_enabled = create_repo("#{@org}-cs-ss-enabled-repo", owner: @org)),
          (@repo_cs_not_enabled = create_repo("#{@org}-cs-not-enabled-repo", owner: @org)),
          (@repo_no_features_enabled = create_repo("#{@org}-none-enabled-repo", owner: @org)),
          (@repo_missing_statuses = create_repo("#{@org}-missing-statuses-repo", owner: @org)),
        ]

        @non_ghas_repos = [
          (@repo_no_statuses = create_repo("#{@org}-no-statuses-repo", owner: @org, enable_ghas: false))
        ]

        @all_repos = @ghas_repos + @non_ghas_repos
      end

      setup do
        @base_rel = RepositorySecurityCenterConfig.left_outer_joins(:repository_security_center_statuses).group(:repository_id)
      end

      context "#apply" do
        test "filters GHAS with inclusive filters" do
          assert_query_count(1) do
            ByGhas.new(["enabled"], []).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = @ghas_repos
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByGhas.new(["not-enabled"], []).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = @non_ghas_repos
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end

        test "filters GHAS with exclusive filters" do
          assert_query_count(1) do
            ByGhas.new([], ["enabled"]).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = @non_ghas_repos
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByGhas.new([], ["not-enabled"]).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = @ghas_repos
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end

        test "filters GHAS with both inclusive and exclusive filters" do
          assert_query_count(1) do
            ByGhas.new(["enabled"], ["not-enabled"]).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = @ghas_repos
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end

          assert_query_count(1) do
            ByGhas.new(["not-enabled"], ["enabled"]).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = @non_ghas_repos
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end

        test "ignores empty filters" do
          assert_query_count(1) do
            ByGhas.new([], []).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = @all_repos
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end

        test "filters by unrecognized filters" do
          assert_query_count(0) do
            ByGhas.new(["failed"], []).apply(@base_rel).to_a
          end.tap do |results|
            expected_repos = []
            assert_same_elements expected_repos.map(&:id), results.map(&:repository_id)
          end
        end
      end

      def create_repo(name, owner:, enable_ghas: true)
        create(:private_repository, name: name, owner: owner).tap do |r|
          create(
            :repository_security_center_config,
            repository: r,
            ghas_enabled: enable_ghas,
          )
        end
      end
    end
  end
end
