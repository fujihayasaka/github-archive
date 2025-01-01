# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module UnifiedAlerts
    class ByRepositoryVisibilityGroupDataQueryTest < GitHub::TestCase
      extend T::Sig
      include ::SecurityOverviewAnalytics::TestFixtures

      fixtures do
        @biz = create(:business)
        @org_admin = create(:user)
        @user_session = create(:user_session, user: @org_admin)
        @org = create(:organization, business: @biz, admin: @org_admin)

        @repo = create(:private_repository, owner: @org)
        create_repo_alerts(repository: @repo)

        @public_repo = create(:public_repository, owner: @org)
        create_repo_alerts(repository: @public_repo, enabled_features: [SecurityFeatures::DEPENDABOT_ALERTS])

        @internal_repo = create(:internal_repository, owner: @org)
        create_repo_alerts(repository: @internal_repo, enabled_features: [SecurityFeatures::CODE_SCANNING])

        @repo_without_alerts = create(:public_repository, owner: @org)
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
            .run("repo.visibility", cursor: "-1")
        end

        assert_raises ArgumentError do
          GroupDataQuery
            .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
            .run("repo.visibility", cursor: "test")
        end
      end

      test "returns list of groups" do
        result = GroupDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("repo.visibility", cursor: "0")
        assert_nil result.previous
        assert_nil result.next

        alert_groups = result.alert_groups
        assert_equal 3, alert_groups.count

        assert_equal "repo.visibility:private", T.must(alert_groups[0])[:key]
        assert_equal "private", T.must(alert_groups[0])[:name]
        assert_equal 3, T.must(alert_groups[0])[:count_critical]
        assert_equal 2, T.must(alert_groups[0])[:count_high]
        assert_equal 2, T.must(alert_groups[0])[:count_medium]
        assert_equal 2, T.must(alert_groups[0])[:count_low]
        assert_equal 10, T.must(alert_groups[0])[:total]

        assert_equal "repo.visibility:internal", T.must(alert_groups[1])[:key]
        assert_equal "internal", T.must(alert_groups[1])[:name]
        assert_equal 1, T.must(alert_groups[1])[:count_critical]
        assert_equal 1, T.must(alert_groups[1])[:count_high]
        assert_equal 1, T.must(alert_groups[1])[:count_medium]
        assert_equal 1, T.must(alert_groups[1])[:count_low]
        assert_equal 5, T.must(alert_groups[1])[:total]

        assert_equal "repo.visibility:public", T.must(alert_groups[2])[:key]
        assert_equal "public", T.must(alert_groups[2])[:name]
        assert_equal 1, T.must(alert_groups[2])[:count_critical]
        assert_equal 1, T.must(alert_groups[2])[:count_high]
        assert_equal 1, T.must(alert_groups[2])[:count_medium]
        assert_equal 1, T.must(alert_groups[2])[:count_low]
        assert_equal 4, T.must(alert_groups[2])[:total]
      end
    end
  end
end
