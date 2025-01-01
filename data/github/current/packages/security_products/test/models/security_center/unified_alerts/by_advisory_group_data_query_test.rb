# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module UnifiedAlerts
    class ByAdvisoryGroupDataQueryTest < GitHub::TestCase
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
        @query = ::Search::Queries::SecurityCenter::QueryParser.new("archived:false")
      end

      test "raises ArgumentError if cursor value is invalid" do
        assert_raises ArgumentError do
          GroupDataQuery
            .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
            .run("dependabot.advisory", cursor: "-1")
        end

        assert_raises ArgumentError do
          GroupDataQuery
            .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
            .run("dependabot.advisory", cursor: "test")
        end
      end

      test "returns list of groups" do
        result = GroupDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("dependabot.advisory", cursor: "0")
        assert_nil result.previous
        assert_nil result.next

        alert_groups = result.alert_groups
        assert_equal 4, alert_groups.count

        alert_group = alert_groups[0]
        assert_equal "dependabot.advisory:GHSA-1234-5678-0001", T.must(alert_group)[:key]
        assert_equal "GHSA-1234-5678-0001", T.must(alert_group)[:name]
        assert_equal 1, T.must(alert_group)[:count_critical]
        assert_equal 1, T.must(alert_group)[:count_high]
        assert_equal 1, T.must(alert_group)[:count_medium]
        assert_equal 1, T.must(alert_group)[:count_low]
        assert_equal 4, T.must(alert_group)[:total]

        alert_group = alert_groups[1]
        assert_equal "dependabot.advisory:GHSA-1234-5678-0003", T.must(alert_group)[:key]
        assert_equal "GHSA-1234-5678-0003", T.must(alert_group)[:name]
        assert_equal 1, T.must(alert_group)[:count_critical]
        assert_equal 1, T.must(alert_group)[:count_high]
        assert_equal 0, T.must(alert_group)[:count_medium]
        assert_equal 0, T.must(alert_group)[:count_low]
        assert_equal 2, T.must(alert_group)[:total]

        alert_group = alert_groups[2]
        assert_equal "dependabot.advisory:GHSA-1234-5678-0002", T.must(alert_group)[:key]
        assert_equal "GHSA-1234-5678-0002", T.must(alert_group)[:name]
        assert_equal 1, T.must(alert_group)[:count_critical]
        assert_equal 0, T.must(alert_group)[:count_high]
        assert_equal 0, T.must(alert_group)[:count_medium]
        assert_equal 0, T.must(alert_group)[:count_low]
        assert_equal 1, T.must(alert_group)[:total]

        alert_group = alert_groups[3]
        assert_equal "dependabot.advisory:GHSA-1234-5678-0004", T.must(alert_group)[:key]
        assert_equal "GHSA-1234-5678-0004", T.must(alert_group)[:name]
        assert_equal 0, T.must(alert_group)[:count_critical]
        assert_equal 0, T.must(alert_group)[:count_high]
        assert_equal 1, T.must(alert_group)[:count_medium]
        assert_equal 1, T.must(alert_group)[:count_low]
        assert_equal 2, T.must(alert_group)[:total]
      end

      test "supports paging and contains next cursor" do
        result = GroupDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("dependabot.advisory", cursor: "1", page_size: 2)
        assert_equal "0", result.previous
        assert_equal "3", result.next

        alert_groups = result.alert_groups
        assert_equal 2, alert_groups.count

        alert_group = alert_groups[0]
        assert_equal "dependabot.advisory:GHSA-1234-5678-0003", T.must(alert_group)[:key]
        assert_equal "GHSA-1234-5678-0003", T.must(alert_group)[:name]
        assert_equal 1, T.must(alert_group)[:count_critical]
        assert_equal 1, T.must(alert_group)[:count_high]
        assert_equal 0, T.must(alert_group)[:count_medium]
        assert_equal 0, T.must(alert_group)[:count_low]
        assert_equal 2, T.must(alert_group)[:total]

        alert_group = alert_groups[1]
        assert_equal "dependabot.advisory:GHSA-1234-5678-0002", T.must(alert_group)[:key]
        assert_equal "GHSA-1234-5678-0002", T.must(alert_group)[:name]
        assert_equal 1, T.must(alert_group)[:count_critical]
        assert_equal 0, T.must(alert_group)[:count_high]
        assert_equal 0, T.must(alert_group)[:count_medium]
        assert_equal 0, T.must(alert_group)[:count_low]
        assert_equal 1, T.must(alert_group)[:total]
      end

      test "returns groups based on enabled feature types only" do
        another_org = create(:organization, business: @biz, admin: @org_admin)
        repo = create(:private_repository, owner: another_org)
        create_repo_alerts(repository: repo, enabled_features: [SecurityFeatures::SECRET_SCANNING])

        result = GroupDataQuery
          .for_organization(another_org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("dependabot.advisory", cursor: "0")
        assert_nil result.previous
        assert_nil result.next

        alert_groups = result.alert_groups
        assert_equal 0, alert_groups.count
      end

      test "returns empty result if no alert data available" do
        another_org = create(:organization, business: @biz, admin: @org_admin)
        repo = create(:private_repository, owner: another_org)
        create_repo_alerts(repository: repo, no_alert_data: true)

        result = GroupDataQuery
          .for_organization(another_org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("dependabot.advisory", cursor: "0")
        assert_nil result.previous
        assert_nil result.next

        alert_groups = result.alert_groups
        assert_equal 0, alert_groups.count
      end
    end
  end
end
