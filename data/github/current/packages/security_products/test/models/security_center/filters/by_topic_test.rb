# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
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

      context "#apply" do
        test "filters by topic - positive" do
          rel = RepositorySecurityCenterConfig.all.left_outer_joins(:repository_security_center_statuses).group(:repository_id)

          filter = ByTopic.new(["lemon"], [], organizations: [@org])
          expected_repos = [@repo_lemon]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByTopic.new(["lime"], [], organizations: [@org])
          expected_repos = [@repo_lime]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByTopic.new(["citrus"], [], organizations: [@org])
          expected_repos = [@repo_lemon, @repo_lime]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByTopic.new(["berry"], [], organizations: [@org, @another_org])
          expected_repos = [@repo_lingonberry, @repo_banana, @repo_blueberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByTopic.new(["fruit"], [], organizations: [@org, @another_org])
          expected_repos = [@repo_lemon, @repo_lime, @repo_lingonberry, @repo_banana, @repo_blueberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByTopic.new(%w[lemon lime], [], organizations: [@org])
          expected_repos = [@repo_lemon, @repo_lime]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByTopic.new(%w[citrus lime], [], organizations: [@org])
          expected_repos = [@repo_lemon, @repo_lime]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByTopic.new(%w[berry lime], [], organizations: [@org])
          expected_repos = [@repo_lime, @repo_lingonberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByTopic.new(%w[fruit lime], [], organizations: [@org])
          expected_repos = [@repo_lemon, @repo_lime, @repo_lingonberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByTopic.new(%w[invalid berry], [], organizations: [@org])
          expected_repos = [@repo_lingonberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)
        end

        test "filters by topic - negative" do
          rel = RepositorySecurityCenterConfig.all.left_outer_joins(:repository_security_center_statuses).group(:repository_id)

          filter = ByTopic.new([], ["lime"], organizations: [@org])
          expected_repos = [@repo_lemon, @repo_lingonberry, @repo_no_topic, @repo_banana, @repo_blueberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByTopic.new([], ["citrus"], organizations: [@org])
          expected_repos = [@repo_lingonberry, @repo_no_topic, @repo_banana, @repo_blueberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByTopic.new([], ["fruit"], organizations: [@org, @another_org])
          expected_repos = [@repo_no_topic]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByTopic.new(["berry"], ["lime"], organizations: [@org])
          expected_repos = [@repo_lingonberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByTopic.new([], %w[lime berry], organizations: [@org, @another_org])
          expected_repos = [@repo_lemon, @repo_no_topic]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByTopic.new([], ["invalid"], organizations: [@org])
          expected_repos = [@repo_lemon, @repo_lime, @repo_lingonberry, @repo_no_topic, @repo_banana, @repo_blueberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByTopic.new(["berry"], ["invalid"], organizations: [@org, @another_org])
          expected_repos = [@repo_lingonberry, @repo_banana, @repo_blueberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByTopic.new([], %w[invalid lime], organizations: [@org])
          expected_repos = [@repo_lemon, @repo_lingonberry, @repo_no_topic, @repo_banana, @repo_blueberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByTopic.new(["berry"], %w[invalid lime], organizations: [@org])
          expected_repos = [@repo_lingonberry]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)
        end

        test "doesn't apply clause if no filters are provided" do
          rel = RepositorySecurityCenterConfig.all
          expected_clause = rel.to_sql

          filter = ByTopic.new(nil, nil, organizations: [@org])
          assert_equal expected_clause, filter.apply(rel).to_sql

          filter = ByTopic.new([], [], organizations: [@org])
          assert_equal expected_clause, filter.apply(rel).to_sql
        end

        test "returns rel.none if no organizations are provided with filters" do
          rel = RepositorySecurityCenterConfig.all

          filter = ByTopic.new(["lemon"], [], organizations: [])
          assert_empty filter.apply(rel)

          filter = ByTopic.new(["lemon"], [], organizations: [])
          assert_empty filter.apply(rel)

          filter = ByTopic.new([], ["berry"], organizations: [])
          assert_empty filter.apply(rel)
        end

        test "returns all results if no organizations and no filters are provided" do
          rel = RepositorySecurityCenterConfig.all

          filter = ByTopic.new([], [], organizations: [])
          assert_equal rel.length, filter.apply(rel).length
        end

        test "returns proper result for is_empty?" do
          assert ByTopic.new(nil, nil, organizations: [@org]).is_empty?
          assert ByTopic.new([], [], organizations: [@org]).is_empty?
          refute ByTopic.new(["berry"], [], organizations: [@org]).is_empty?
          refute ByTopic.new([], ["berry"], organizations: [@org]).is_empty?
        end

        test "applies where clause with positive filters" do
          rel = RepositorySecurityCenterConfig.all
          prefix_sql = rel.to_sql

          filter = ByTopic.new(["lemon"], [], organizations: [@org])
          expected_clause = "WHERE `repository_security_center_configs`.`repository_id` = #{@repo_lemon.id}"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip

          filter = ByTopic.new(["citrus"], [], organizations: [@org])
          expected_clause = "WHERE `repository_security_center_configs`.`repository_id` IN (#{@repo_lemon.id}, #{@repo_lime.id})"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
        end

        test "applies where clause with positive filters across multiple orgs" do
          rel = RepositorySecurityCenterConfig.all
          prefix_sql = rel.to_sql

          filter = ByTopic.new(["berry"], [], organizations: [@org, @another_org])
          expected_clause = "WHERE `repository_security_center_configs`.`repository_id` IN (#{@repo_lingonberry.id}, #{@repo_banana.id}, #{@repo_blueberry.id})"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip

          filter = ByTopic.new(["fruit"], [], organizations: [@org, @another_org])
          expected_clause = "WHERE `repository_security_center_configs`.`repository_id` IN (#{@repo_lemon.id}, #{@repo_lime.id}, #{@repo_lingonberry.id}, #{@repo_banana.id}, #{@repo_blueberry.id})"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
        end

        test "applies where clause with negated filters" do
          rel = RepositorySecurityCenterConfig.all
          prefix_sql = rel.to_sql

          filter = ByTopic.new([], ["lemon"], organizations: [@org])
          expected_clause = "WHERE `repository_security_center_configs`.`repository_id` != #{@repo_lemon.id}"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip

          filter = ByTopic.new([], ["citrus"], organizations: [@org])
          expected_clause = "WHERE `repository_security_center_configs`.`repository_id` NOT IN (#{@repo_lemon.id}, #{@repo_lime.id})"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
        end

        test "applies where clause with negated filters across multiple orgs" do
          rel = RepositorySecurityCenterConfig.all
          prefix_sql = rel.to_sql

          filter = ByTopic.new([], ["berry"], organizations: [@org, @another_org])
          expected_clause = "WHERE `repository_security_center_configs`.`repository_id` NOT IN (#{@repo_lingonberry.id}, #{@repo_banana.id}, #{@repo_blueberry.id})"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip

          filter = ByTopic.new([], ["fruit"], organizations: [@org, @another_org])
          expected_clause = "WHERE `repository_security_center_configs`.`repository_id` NOT IN (#{@repo_lemon.id}, #{@repo_lime.id}, #{@repo_lingonberry.id}, #{@repo_banana.id}, #{@repo_blueberry.id})"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
        end
      end

      def create_repo(name, owner:)
        create(:private_repository, name: name, owner: owner).tap do |repo|
          create(:repository_security_center_config, repository: repo)
          RepositorySecurityCenterStatus.feature_types.keys.each do |feature_type|
            create(:repository_security_center_status, repository: repo, feature_type: feature_type, scanning_status: :enrolled)
          end
        end
      end
    end
  end
end
