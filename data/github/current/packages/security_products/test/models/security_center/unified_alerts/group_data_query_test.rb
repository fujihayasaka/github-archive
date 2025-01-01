# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module UnifiedAlerts
    class GroupDataQueryTest < GitHub::TestCase
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

      test "returns empty result with unknown group key" do
        result = GroupDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("woof", cursor: "0")
        assert_nil result.previous
        assert_nil result.next
        assert_empty result.alert_groups
      end

      test "returns empty result if no revision data available" do
        org = create(:organization, business: @biz, admin: @org_admin)
        repo = create(:private_repository, owner: org)

        ::SecurityCenter::UnifiedAlerts::Groups::GroupLookup::GROUP_KEY_TO_TYPE_MAPPINGS.each do |(key, _)|
          result = GroupDataQuery
            .for_organization(org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
            .run(key, cursor: "0")

          assert_nil result.previous
          assert_nil result.next
          assert_empty result.alert_groups
        end
      end
    end
  end
end
