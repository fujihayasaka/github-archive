# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module UnifiedAlerts
    class CountsDataQueryTest < GitHub::TestCase
      extend T::Sig
      include ::SecurityOverviewAnalytics::TestFixtures

      fixtures do
        @biz = create(:business)
        @org_admin = create(:user)
        @user_session = create(:user_session, user: @org_admin)
        @org = create(:organization, business: @biz, admin: @org_admin)
        @repo = create(:private_repository, owner: @org)

        @archived_repo = create(:archived_repository, owner: @org)
        create_repo_alerts(repository: @archived_repo)
      end

      setup do
        SecurityFeatures.stubs(:visible_features).returns([
          SecurityFeatures::SECRET_SCANNING ,
          SecurityFeatures::CODE_SCANNING,
          SecurityFeatures::DEPENDABOT_ALERTS,
        ])
        @query = ::Search::Queries::SecurityCenter::QueryParser.new("is:open archived:false")
      end

      test "returns alert counts" do
        create_repo_alerts(repository: @repo)

        result = CountsDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run

        assert_equal 10, result.open
        assert_equal 15, result.closed
      end

      test "returns alert counts of enabled feature types only" do
        create_repo_alerts(repository: @repo, enabled_features: [SecurityFeatures::CODE_SCANNING])

        result = CountsDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run

        assert_equal 5, result.open
        assert_equal 5, result.closed
      end

      test "returns 0 counts if no revision data available" do
        create_repo_alerts(repository: @repo, no_alert_data: true)

        result = CountsDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run

        assert_equal 0, result.open
        assert_equal 0, result.closed
      end
    end
  end
end
