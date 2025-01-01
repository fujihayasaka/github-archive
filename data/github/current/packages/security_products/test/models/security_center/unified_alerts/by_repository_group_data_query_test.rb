# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module UnifiedAlerts
    class ByRepositoryGroupDataQueryTest < GitHub::TestCase
      extend T::Sig
      include ::SecurityOverviewAnalytics::TestFixtures

      fixtures do
        @biz = create(:business)
        @org_admin = create(:user)
        @user_session = create(:user_session, user: @org_admin)
        @org = create(:organization, business: @biz, admin: @org_admin)

        @repo = create(:private_repository, owner: @org)
        create_repo_alerts(repository: @repo)

        @repo_with_dbot_alerts_only = create(:private_repository, owner: @org)
        create_repo_alerts(repository: @repo_with_dbot_alerts_only, enabled_features: [SecurityFeatures::DEPENDABOT_ALERTS])

        @repo_with_cs_alerts_only = create(:private_repository, owner: @org)
        create_repo_alerts(repository: @repo_with_cs_alerts_only, enabled_features: [SecurityFeatures::CODE_SCANNING])

        @repo_with_ss_alerts_only = create(:private_repository, owner: @org)
        create_repo_alerts(repository: @repo_with_ss_alerts_only, enabled_features: [SecurityFeatures::SECRET_SCANNING])

        @repo_without_alerts = create(:private_repository, owner: @org)
        create_repo_alerts(repository: @repo_without_alerts, no_alert_data: true)
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
            .run("repo", cursor: "-1")
        end

        assert_raises ArgumentError do
          GroupDataQuery
            .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
            .run("repo", cursor: "test")
        end
      end

      test "returns list of groups" do
        result = GroupDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("repo", cursor: "0")
        assert_nil result.previous
        assert_nil result.next

        alert_groups = result.alert_groups
        assert_equal 4, alert_groups.count

        assert_equal "repo:#{@repo.name}", T.must(alert_groups[0])[:key]
        assert_equal @repo.name, T.must(alert_groups[0])[:name]
        assert_equal 3, T.must(alert_groups[0])[:count_critical]
        assert_equal 2, T.must(alert_groups[0])[:count_high]
        assert_equal 2, T.must(alert_groups[0])[:count_medium]
        assert_equal 2, T.must(alert_groups[0])[:count_low]
        assert_equal 10, T.must(alert_groups[0])[:total]

        assert_equal "repo:#{@repo_with_cs_alerts_only.name}", T.must(alert_groups[1])[:key]
        assert_equal @repo_with_cs_alerts_only.name, T.must(alert_groups[1])[:name]
        assert_equal 1, T.must(alert_groups[1])[:count_critical]
        assert_equal 1, T.must(alert_groups[1])[:count_high]
        assert_equal 1, T.must(alert_groups[1])[:count_medium]
        assert_equal 1, T.must(alert_groups[1])[:count_low]
        assert_equal 5, T.must(alert_groups[1])[:total]

        assert_equal "repo:#{@repo_with_dbot_alerts_only.name}", T.must(alert_groups[2])[:key]
        assert_equal @repo_with_dbot_alerts_only.name, T.must(alert_groups[2])[:name]
        assert_equal 1, T.must(alert_groups[2])[:count_critical]
        assert_equal 1, T.must(alert_groups[2])[:count_high]
        assert_equal 1, T.must(alert_groups[2])[:count_medium]
        assert_equal 1, T.must(alert_groups[2])[:count_low]
        assert_equal 4, T.must(alert_groups[2])[:total]

        assert_equal "repo:#{@repo_with_ss_alerts_only.name}", T.must(alert_groups[3])[:key]
        assert_equal @repo_with_ss_alerts_only.name, T.must(alert_groups[3])[:name]
        assert_equal 1, T.must(alert_groups[3])[:count_critical]
        assert_equal 0, T.must(alert_groups[3])[:count_high]
        assert_equal 0, T.must(alert_groups[3])[:count_medium]
        assert_equal 0, T.must(alert_groups[3])[:count_low]
        assert_equal 1, T.must(alert_groups[3])[:total]
      end

      test "supports paging and contains next cursor" do
        result = GroupDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("repo", cursor: "1", page_size: 2)
        assert_equal "0", result.previous
        assert_equal "3", result.next

        alert_groups = result.alert_groups
        assert_equal 2, alert_groups.count

        assert_equal "repo:#{@repo_with_cs_alerts_only.name}", T.must(alert_groups[0])[:key]
        assert_equal @repo_with_cs_alerts_only.name, T.must(alert_groups[0])[:name]
        assert_equal 1, T.must(alert_groups[0])[:count_critical]
        assert_equal 1, T.must(alert_groups[0])[:count_high]
        assert_equal 1, T.must(alert_groups[0])[:count_medium]
        assert_equal 1, T.must(alert_groups[0])[:count_low]
        assert_equal 5, T.must(alert_groups[0])[:total]

        assert_equal "repo:#{@repo_with_dbot_alerts_only.name}", T.must(alert_groups[1])[:key]
        assert_equal @repo_with_dbot_alerts_only.name, T.must(alert_groups[1])[:name]
        assert_equal 1, T.must(alert_groups[1])[:count_critical]
        assert_equal 1, T.must(alert_groups[1])[:count_high]
        assert_equal 1, T.must(alert_groups[1])[:count_medium]
        assert_equal 1, T.must(alert_groups[1])[:count_low]
        assert_equal 4, T.must(alert_groups[1])[:total]
      end
    end
  end
end
