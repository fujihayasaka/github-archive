# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module UnifiedAlerts
    class ByToolGroupDataQueryTest < GitHub::TestCase
      extend T::Sig
      include ::SecurityOverviewAnalytics::TestFixtures

      fixtures do
        @biz = create(:business)
        @org_admin = create(:user)
        @user_session = create(:user_session, user: @org_admin)
        @org = create(:organization, business: @biz, admin: @org_admin)
        @repo = create(:private_repository, owner: @org)
        create_repo_alerts(repository: @repo)
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
            .run("tool", cursor: "-1")
        end

        assert_raises ArgumentError do
          GroupDataQuery
            .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
            .run("tool", cursor: "test")
        end
      end

      test "returns list of groups" do
        result = GroupDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("tool", cursor: "0")
        assert_nil result.previous
        assert_nil result.next

        alert_groups = result.alert_groups
        assert_equal 4, alert_groups.count

        assert_equal "tool:dependabot", T.must(alert_groups[0])[:key]
        assert_equal "Dependabot", T.must(alert_groups[0])[:name]
        assert_equal 1, T.must(alert_groups[0])[:count_critical]
        assert_equal 1, T.must(alert_groups[0])[:count_high]
        assert_equal 1, T.must(alert_groups[0])[:count_medium]
        assert_equal 1, T.must(alert_groups[0])[:count_low]
        assert_equal 4, T.must(alert_groups[0])[:total]

        assert_equal "tool:codeql", T.must(alert_groups[1])[:key]
        assert_equal "CodeQL", T.must(alert_groups[1])[:name]
        assert_equal 1, T.must(alert_groups[1])[:count_critical]
        assert_equal 1, T.must(alert_groups[1])[:count_high]
        assert_equal 0, T.must(alert_groups[1])[:count_medium]
        assert_equal 0, T.must(alert_groups[1])[:count_low]
        assert_equal 2, T.must(alert_groups[1])[:total]

        assert_equal "tool:secret-scanning", T.must(alert_groups[2])[:key]
        assert_equal "Secret scanning", T.must(alert_groups[2])[:name]
        assert_equal 1, T.must(alert_groups[2])[:count_critical]
        assert_equal 0, T.must(alert_groups[2])[:count_high]
        assert_equal 0, T.must(alert_groups[2])[:count_medium]
        assert_equal 0, T.must(alert_groups[2])[:count_low]
        assert_equal 1, T.must(alert_groups[2])[:total]

        assert_equal "tool:some-tool", T.must(alert_groups[3])[:key]
        assert_equal "some-tool", T.must(alert_groups[3])[:name]
        assert_equal 0, T.must(alert_groups[3])[:count_critical]
        assert_equal 0, T.must(alert_groups[3])[:count_high]
        assert_equal 1, T.must(alert_groups[3])[:count_medium]
        assert_equal 1, T.must(alert_groups[3])[:count_low]
        assert_equal 3, T.must(alert_groups[3])[:total]
      end

      test "supports paging and contains next cursor" do
        result = GroupDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("tool", cursor: "1", page_size: 2)
        assert_equal "0", result.previous
        assert_equal "3", result.next

        alert_groups = result.alert_groups
        assert_equal 2, alert_groups.count

        assert_equal "tool:codeql", T.must(alert_groups[0])[:key]
        assert_equal "CodeQL", T.must(alert_groups[0])[:name]
        assert_equal 1, T.must(alert_groups[0])[:count_critical]
        assert_equal 1, T.must(alert_groups[0])[:count_high]
        assert_equal 0, T.must(alert_groups[0])[:count_medium]
        assert_equal 0, T.must(alert_groups[0])[:count_low]
        assert_equal 2, T.must(alert_groups[0])[:total]

        assert_equal "tool:secret-scanning", T.must(alert_groups[1])[:key]
        assert_equal "Secret scanning", T.must(alert_groups[1])[:name]
        assert_equal 1, T.must(alert_groups[1])[:count_critical]
        assert_equal 0, T.must(alert_groups[1])[:count_high]
        assert_equal 0, T.must(alert_groups[1])[:count_medium]
        assert_equal 0, T.must(alert_groups[1])[:count_low]
        assert_equal 1, T.must(alert_groups[1])[:total]
      end

      test "returns groups based on enabled feature types only" do
        another_org = create(:organization, business: @biz, admin: @org_admin)
        repo = create(:private_repository, owner: another_org)
        create_repo_alerts(repository: repo, enabled_features: [SecurityFeatures::SECRET_SCANNING])

        result = GroupDataQuery
          .for_organization(another_org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("tool", cursor: "0")
        assert_nil result.previous
        assert_nil result.next

        alert_groups = result.alert_groups
        assert_equal 1, alert_groups.count

        assert_equal "tool:secret-scanning", T.must(alert_groups[0])[:key]
        assert_equal "Secret scanning", T.must(alert_groups[0])[:name]
        assert_equal 1, T.must(alert_groups[0])[:count_critical]
        assert_equal 0, T.must(alert_groups[0])[:count_high]
        assert_equal 0, T.must(alert_groups[0])[:count_medium]
        assert_equal 0, T.must(alert_groups[0])[:count_low]
        assert_equal 1, T.must(alert_groups[0])[:total]
      end

      test "returns empty result if no revision data available" do
        another_org = create(:organization, business: @biz, admin: @org_admin)
        repo = create(:private_repository, owner: another_org)
        create_repo_alerts(repository: repo, no_alert_data: true)

        result = GroupDataQuery
          .for_organization(another_org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("tool", cursor: "0")
        assert_nil result.previous
        assert_nil result.next

        alert_groups = result.alert_groups
        assert_equal 0, alert_groups.count
      end
    end
  end
end
