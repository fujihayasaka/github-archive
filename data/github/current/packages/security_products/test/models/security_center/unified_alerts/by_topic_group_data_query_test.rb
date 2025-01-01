# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module UnifiedAlerts
    class ByTopicGroupDataQueryTest < GitHub::TestCase
      extend T::Sig
      include ::SecurityOverviewAnalytics::TestFixtures

      fixtures do
        @biz = create(:business)
        @org_admin = create(:user)
        @user_session = create(:user_session, user: @org_admin)
        @org = create(:organization, business: @biz, admin: @org_admin)

        @repo = create(:private_repository, owner: @org)
        create_repo_alerts(repository: @repo)

        repo_banana = create(:internal_repository, name: "banana", owner: @org)
        create_repo_alerts(repository: repo_banana, enabled_features: [SecurityFeatures::SECRET_SCANNING])
        repo_lemon = create(:internal_repository, name: "lemon", owner: @org)
        create_repo_alerts(repository: repo_lemon, enabled_features: [SecurityFeatures::SECRET_SCANNING])
        repo_lime = create(:internal_repository, name: "lime", owner: @org)
        create_repo_alerts(repository: repo_lime, no_alert_data: true)

        @fruit = create(:topic, name: "fruit").tap do |topic|
          create(:repository_topic, topic: topic, repository: @repo)
          create(:repository_topic, topic: topic, repository: repo_lemon)
          create(:repository_topic, topic: topic, repository: repo_lime)
          create(:repository_topic, topic: topic, repository: repo_banana)
        end
        @fruit_rejected = create(:topic, name: "fruit-rejected").tap do |topic|
          create(:repository_topic, topic: topic, repository: repo_lemon, state: :declined_not_relevant)
          create(:repository_topic, topic: topic, repository: repo_lime, state: :declined_not_relevant)
          create(:repository_topic, topic: topic, repository: @repo, state: :declined_not_relevant)
          create(:repository_topic, topic: topic, repository: repo_banana, state: :declined_not_relevant)
        end
        @berry = create(:topic, name: "berry").tap do |topic|
          create(:repository_topic, topic: topic, repository: @repo)
          create(:repository_topic, topic: topic, repository: repo_banana)
        end
        @citrus = create(:topic, name: "citrus").tap do |topic|
          create(:repository_topic, topic: topic, repository: repo_lemon)
          create(:repository_topic, topic: topic, repository: repo_lime)
        end
        @lime = create(:topic, name: "lime").tap do |topic|
          create(:repository_topic, topic: topic, repository: repo_lime)
        end
      end

      setup do
        SecurityFeatures.stubs(:visible_features).returns([
          SecurityFeatures::SECRET_SCANNING ,
          SecurityFeatures::CODE_SCANNING,
          SecurityFeatures::DEPENDABOT_ALERTS,
        ])
        @query = ::Search::Queries::SecurityCenter::QueryParser.new("is:open archived:false")
      end

      test "raises ArgumentError if cursor value is invalid" do
        assert_raises ArgumentError do
          GroupDataQuery
            .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
            .run("topic", cursor: "-1")
        end

        assert_raises ArgumentError do
          GroupDataQuery
            .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
            .run("topic", cursor: "test")
        end
      end

      test "returns empty list when no topics" do
        org = create(:organization, business: @biz, admin: @org_admin)
        repo = create(:private_repository, owner: org)
        create_repo_alerts(repository: repo)

        result = GroupDataQuery
          .for_organization(org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("topic", cursor: "0")

        assert_nil result.previous
        assert_nil result.next
        assert_empty result.alert_groups
      end

      test "returns list of groups" do
        result = GroupDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("topic", cursor: "0")
        assert_nil result.previous
        assert_nil result.next

        alert_groups = result.alert_groups
        assert_equal 4, alert_groups.count

        assert_equal "topic:#{@fruit.name}", T.must(alert_groups[0])[:key]
        assert_equal @fruit.name, T.must(alert_groups[0])[:name]
        assert_equal 5, T.must(alert_groups[0])[:count_critical]
        assert_equal 2, T.must(alert_groups[0])[:count_high]
        assert_equal 2, T.must(alert_groups[0])[:count_medium]
        assert_equal 2, T.must(alert_groups[0])[:count_low]
        assert_equal 12, T.must(alert_groups[0])[:total]

        assert_equal "topic:#{@berry.name}", T.must(alert_groups[1])[:key]
        assert_equal @berry.name, T.must(alert_groups[1])[:name]
        assert_equal 4, T.must(alert_groups[1])[:count_critical]
        assert_equal 2, T.must(alert_groups[1])[:count_high]
        assert_equal 2, T.must(alert_groups[1])[:count_medium]
        assert_equal 2, T.must(alert_groups[1])[:count_low]
        assert_equal 11, T.must(alert_groups[1])[:total]

        assert_equal "topic:#{@citrus.name}", T.must(alert_groups[2])[:key]
        assert_equal @citrus.name, T.must(alert_groups[2])[:name]
        assert_equal 1, T.must(alert_groups[2])[:count_critical]
        assert_equal 0, T.must(alert_groups[2])[:count_high]
        assert_equal 0, T.must(alert_groups[2])[:count_medium]
        assert_equal 0, T.must(alert_groups[2])[:count_low]
        assert_equal 1, T.must(alert_groups[2])[:total]

        assert_equal "topic:#{@lime.name}", T.must(alert_groups[3])[:key]
        assert_equal @lime.name, T.must(alert_groups[3])[:name]
        assert_equal 0, T.must(alert_groups[3])[:count_critical]
        assert_equal 0, T.must(alert_groups[3])[:count_high]
        assert_equal 0, T.must(alert_groups[3])[:count_medium]
        assert_equal 0, T.must(alert_groups[3])[:count_low]
        assert_equal 0, T.must(alert_groups[3])[:total]
      end

      test "supports paging and contains next cursor" do
        result = GroupDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("topic", cursor: "1", page_size: 2)
        assert_equal "0", result.previous
        assert_equal "3", result.next

        alert_groups = result.alert_groups
        assert_equal 2, alert_groups.count

        assert_equal "topic:#{@berry.name}", T.must(alert_groups[0])[:key]
        assert_equal @berry.name, T.must(alert_groups[0])[:name]
        assert_equal 4, T.must(alert_groups[0])[:count_critical]
        assert_equal 2, T.must(alert_groups[0])[:count_high]
        assert_equal 2, T.must(alert_groups[0])[:count_medium]
        assert_equal 2, T.must(alert_groups[0])[:count_low]
        assert_equal 11, T.must(alert_groups[0])[:total]

        assert_equal "topic:#{@citrus.name}", T.must(alert_groups[1])[:key]
        assert_equal @citrus.name, T.must(alert_groups[1])[:name]
        assert_equal 1, T.must(alert_groups[1])[:count_critical]
        assert_equal 0, T.must(alert_groups[1])[:count_high]
        assert_equal 0, T.must(alert_groups[1])[:count_medium]
        assert_equal 0, T.must(alert_groups[1])[:count_low]
        assert_equal 1, T.must(alert_groups[1])[:total]
      end
    end
  end
end
