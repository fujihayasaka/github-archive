# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    class ByTopicTest < GitHub::TestCase
      fixtures do
        @org = create(:organization)
        @another_org = create(:organization)

        @repo_lemon = create_repo("lemon", owner: @org)
        @repo_lime = create_repo("lime", owner: @org)
        @repo_lingonberry = create_repo("lingonberry", owner: @org)
        @repo_banana = create_repo("banana", owner: @another_org)
        @repo_blueberry = create_repo("blueberry", owner: @another_org)
        @repo_no_topic = create_repo("no-topics", owner: @org)

        # repo not owned by the org which also links to all topics
        @repo_unowned = create(:private_repository, owner: create(:user))

        create(:topic, name: "fruit").tap do |topic|
          create(:repository_topic, topic: topic, repository: @repo_lemon)
          create(:repository_topic, topic: topic, repository: @repo_lime)
          create(:repository_topic, topic: topic, repository: @repo_lingonberry)
          create(:repository_topic, topic: topic, repository: @repo_banana)
          create(:repository_topic, topic: topic, repository: @repo_blueberry)
          create(:repository_topic, topic: topic, repository: @repo_unowned)
        end
        create(:topic, name: "berry").tap do |topic|
          create(:repository_topic, topic: topic, repository: @repo_lingonberry)
          create(:repository_topic, topic: topic, repository: @repo_banana)
          create(:repository_topic, topic: topic, repository: @repo_blueberry)
          create(:repository_topic, topic: topic, repository: @repo_unowned)
        end
        create(:topic, name: "citrus").tap do |topic|
          create(:repository_topic, topic: topic, repository: @repo_lemon)
          create(:repository_topic, topic: topic, repository: @repo_lime)
          create(:repository_topic, topic: topic, repository: @repo_unowned)
        end
        create(:topic, name: "lemon").tap do |topic|
          create(:repository_topic, topic: topic, repository: @repo_lemon)
          create(:repository_topic, topic: topic, repository: @repo_unowned)
        end
        create(:topic, name: "lime").tap do |topic|
          create(:repository_topic, topic: topic, repository: @repo_lime)
          create(:repository_topic, topic: topic, repository: @repo_unowned)
        end
      end

      setup do
        @base_rel = Repository.where(organization_id: @org.id)
      end

      context "#apply" do
        test "filters by topic - positive" do
          filter = ByTopic.new(["lemon"], [], organizations: [@org])
          expected_repos = [@repo_lemon]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByTopic.new(["lime"], [], organizations: [@org])
          expected_repos = [@repo_lime]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByTopic.new(["citrus"], [], organizations: [@org])
          expected_repos = [@repo_lemon, @repo_lime]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByTopic.new(["berry"], [], organizations: [@org])
          expected_repos = [@repo_lingonberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByTopic.new(["fruit"], [], organizations: [@org])
          expected_repos = [@repo_lemon, @repo_lime, @repo_lingonberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByTopic.new(%w[lemon lime], [], organizations: [@org])
          expected_repos = [@repo_lemon, @repo_lime]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByTopic.new(%w[citrus lime], [], organizations: [@org])
          expected_repos = [@repo_lemon, @repo_lime]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByTopic.new(%w[berry lime], [], organizations: [@org])
          expected_repos = [@repo_lime, @repo_lingonberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByTopic.new(%w[fruit lime], [], organizations: [@org])
          expected_repos = [@repo_lemon, @repo_lime, @repo_lingonberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByTopic.new(%w[invalid berry], [], organizations: [@org])
          expected_repos = [@repo_lingonberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)
        end

        test "filters by topic - negative" do
          filter = ByTopic.new([], ["lime"], organizations: [@org])
          expected_repos = [@repo_lemon, @repo_lingonberry, @repo_no_topic]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByTopic.new([], ["citrus"], organizations: [@org])
          expected_repos = [@repo_lingonberry, @repo_no_topic]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByTopic.new([], ["fruit"], organizations: [@org])
          expected_repos = [@repo_no_topic]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByTopic.new(["berry"], ["lime"], organizations: [@org])
          expected_repos = [@repo_lingonberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByTopic.new([], %w[lime berry], organizations: [@org])
          expected_repos = [@repo_lemon, @repo_no_topic]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByTopic.new([], ["invalid"], organizations: [@org])
          expected_repos = [@repo_lemon, @repo_lime, @repo_lingonberry, @repo_no_topic]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByTopic.new(["berry"], ["invalid"], organizations: [@org])
          expected_repos = [@repo_lingonberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByTopic.new([], %w[invalid lime], organizations: [@org])
          expected_repos = [@repo_lemon, @repo_lingonberry, @repo_no_topic]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)

          filter = ByTopic.new(["berry"], %w[invalid lime], organizations: [@org])
          expected_repos = [@repo_lingonberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_rel).map(&:repository_id)
        end

        test "doesn't apply clause if no filters are provided" do
          expected_clause = @base_rel.to_sql

          filter = ByTopic.new(nil, nil, organizations: [@org])
          assert_equal expected_clause, filter.apply(@base_rel).to_sql

          filter = ByTopic.new([], [], organizations: [@org])
          assert_equal expected_clause, filter.apply(@base_rel).to_sql
        end

        test "applies where clause with positive filters" do
          rel = Repository.all
          prefix_sql = rel.to_sql

          filter = ByTopic.new(["lemon"], [], organizations: [@org])
          expected_clause = "WHERE `soa_repositories`.`repository_id` = #{@repo_lemon.id}"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip

          filter = ByTopic.new(["citrus"], [], organizations: [@org])
          expected_clause = "WHERE `soa_repositories`.`repository_id` IN (#{@repo_lemon.id}, #{@repo_lime.id})"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
        end

        test "applies where clause with positive filters across multiple orgs" do
          rel = Repository.all
          prefix_sql = rel.to_sql

          filter = ByTopic.new(["berry"], [], organizations: [@org])
          expected_clause = "WHERE `soa_repositories`.`repository_id` = #{@repo_lingonberry.id}"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip

          filter = ByTopic.new(["fruit"], [], organizations: [@org])
          expected_clause = "WHERE `soa_repositories`.`repository_id` IN (#{@repo_lemon.id}, #{@repo_lime.id}, #{@repo_lingonberry.id})"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
        end

        test "applies where clause with negated filters" do
          rel = Repository.all
          prefix_sql = rel.to_sql

          filter = ByTopic.new([], ["lemon"], organizations: [@org])
          expected_clause = "WHERE `soa_repositories`.`repository_id` != #{@repo_lemon.id}"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip

          filter = ByTopic.new([], ["citrus"], organizations: [@org])
          expected_clause = "WHERE `soa_repositories`.`repository_id` NOT IN (#{@repo_lemon.id}, #{@repo_lime.id})"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
        end
      end

      context "#is_empty?" do
        test "returns proper result for is_empty?" do
          assert ByTopic.new(nil, nil, organizations: [@org]).is_empty?
          assert ByTopic.new([], [], organizations: [@org]).is_empty?
          refute ByTopic.new(["berry"], [], organizations: [@org]).is_empty?
          refute ByTopic.new([], ["berry"], organizations: [@org]).is_empty?
          refute ByTopic.new(["woof"], ["berry"], organizations: [@org]).is_empty?
        end
      end

      context "#has_incl_filters?" do
        test "returns proper result for has_incl_filters?" do
          refute ByTopic.new(nil, nil, organizations: [@org]).has_incl_filters?
          refute ByTopic.new([], [], organizations: [@org]).has_incl_filters?
          assert ByTopic.new(["berry"], [], organizations: [@org]).has_incl_filters?
          refute ByTopic.new([], ["berry"], organizations: [@org]).has_incl_filters?
          assert ByTopic.new(["woof"], ["berry"], organizations: [@org]).has_incl_filters?
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
