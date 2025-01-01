# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module UnifiedAlerts
    class ByTeamGroupDataQueryTest < GitHub::TestCase
      extend T::Sig
      include ::SecurityOverviewAnalytics::TestFixtures

      fixtures do
        @biz = create(:business)
        @org_admin = create(:user)
        @user_session = create(:user_session, user: @org_admin)
        @org = create(:organization, business: @biz, admin: @org_admin)

        @repo = create(:internal_repository, name: "#{@org}-repo-admin", owner: @org)
        create_repo_alerts(repository: @repo)

        repo_team_ss_only = create(:internal_repository, name: "#{@org}-repo-team-ss-only", owner: @org)
        create_repo_alerts(repository: repo_team_ss_only, enabled_features: [SecurityFeatures::SECRET_SCANNING])

        repo_team_no_alert = create(:internal_repository, name: "#{@org}-repo-team-no-alert", owner: @org)
        create_repo_alerts(repository: repo_team_no_alert, no_alert_data: true)

        @public_team = create(:public_team, organization: @org, name: "#{@org}-public-team").tap do |t|
          t.add_repository(@repo, :admin)
          t.add_repository(repo_team_ss_only, :write)
        end
        @secret_team = create(:secret_team, organization: @org, name: "#{@org}-secret-team").tap do |t|
          t.add_repository(@repo, :admin)
          t.add_repository(repo_team_ss_only, :read)
        end
        @ss_only_team = create(:secret_team, organization: @org, name: "#{@org}-ss-only-team").tap do |t|
          t.add_repository(repo_team_ss_only, :admin)
        end
        @no_alert_team = create(:secret_team, organization: @org, name: "#{@org}-no-alert-team").tap do |t|
          t.add_repository(repo_team_no_alert, :admin)
        end
        no_repo_public_team = create(:public_team, organization: @org, name: "#{@org}-no-repo-public-team")
        no_repo_secret_team = create(:secret_team, organization: @org, name: "#{@org}-no-repo-secret-team")
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
            .run("team", cursor: "-1")
        end

        assert_raises ArgumentError do
          GroupDataQuery
            .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
            .run("team", cursor: "test")
        end
      end

      test "returns empty list when no teams" do
        org = create(:organization, business: @biz, admin: @org_admin)
        repo = create(:repository, owner: org)
        create_repo_alerts(repository: repo) # Data accessible by no team

        result = GroupDataQuery
          .for_organization(org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("team", cursor: "0")

        assert_nil result.previous
        assert_nil result.next
        assert_empty result.alert_groups
      end

      test "returns empty list when teams with no repos" do
        org = create(:organization, business: @biz, admin: @org_admin)
        repo = create(:repository, owner: org)
        create_repo_alerts(repository: repo) # Data accessible by no team

        create(:public_team, organization: org, name: "#{org}-no-repo-public-team")
        create(:secret_team, organization: org, name: "#{org}-no-repo-secret-team")

        result = GroupDataQuery
          .for_organization(org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("team", cursor: "0")

        assert_nil result.previous
        assert_nil result.next
        assert_empty result.alert_groups
      end

      test "returns list of groups" do
        result = GroupDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("team", cursor: "0")
        assert_nil result.previous
        assert_nil result.next

        alert_groups = result.alert_groups
        assert_equal 4, alert_groups.count

        assert_equal "team:#{@public_team.name}", T.must(alert_groups[0])[:key]
        assert_equal @public_team.name, T.must(alert_groups[0])[:name]
        assert_equal 4, T.must(alert_groups[0])[:count_critical]
        assert_equal 2, T.must(alert_groups[0])[:count_high]
        assert_equal 2, T.must(alert_groups[0])[:count_medium]
        assert_equal 2, T.must(alert_groups[0])[:count_low]
        assert_equal 11, T.must(alert_groups[0])[:total]

        assert_equal "team:#{@secret_team.name}", T.must(alert_groups[1])[:key]
        assert_equal @secret_team.name, T.must(alert_groups[1])[:name]
        assert_equal 3, T.must(alert_groups[1])[:count_critical]
        assert_equal 2, T.must(alert_groups[1])[:count_high]
        assert_equal 2, T.must(alert_groups[1])[:count_medium]
        assert_equal 2, T.must(alert_groups[1])[:count_low]
        assert_equal 10, T.must(alert_groups[1])[:total]

        assert_equal "team:#{@ss_only_team.name}", T.must(alert_groups[2])[:key]
        assert_equal @ss_only_team.name, T.must(alert_groups[2])[:name]
        assert_equal 1, T.must(alert_groups[2])[:count_critical]
        assert_equal 0, T.must(alert_groups[2])[:count_high]
        assert_equal 0, T.must(alert_groups[2])[:count_medium]
        assert_equal 0, T.must(alert_groups[2])[:count_low]
        assert_equal 1, T.must(alert_groups[2])[:total]

        assert_equal "team:#{@no_alert_team.name}", T.must(alert_groups[3])[:key]
        assert_equal @no_alert_team.name, T.must(alert_groups[3])[:name]
        assert_equal 0, T.must(alert_groups[3])[:count_critical]
        assert_equal 0, T.must(alert_groups[3])[:count_high]
        assert_equal 0, T.must(alert_groups[3])[:count_medium]
        assert_equal 0, T.must(alert_groups[3])[:count_low]
        assert_equal 0, T.must(alert_groups[3])[:total]
      end

      test "supports paging and contains next cursor" do
        result = GroupDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("team", cursor: "1", page_size: 2)
        assert_equal "0", result.previous
        assert_equal "3", result.next

        alert_groups = result.alert_groups
        assert_equal 2, alert_groups.count

        assert_equal "team:#{@secret_team.name}", T.must(alert_groups[0])[:key]
        assert_equal @secret_team.name, T.must(alert_groups[0])[:name]
        assert_equal 3, T.must(alert_groups[0])[:count_critical]
        assert_equal 2, T.must(alert_groups[0])[:count_high]
        assert_equal 2, T.must(alert_groups[0])[:count_medium]
        assert_equal 2, T.must(alert_groups[0])[:count_low]
        assert_equal 10, T.must(alert_groups[0])[:total] # 3 repo * 4 alerts

        assert_equal "team:#{@ss_only_team.name}", T.must(alert_groups[1])[:key]
        assert_equal @ss_only_team.name, T.must(alert_groups[1])[:name]
        assert_equal 1, T.must(alert_groups[1])[:count_critical]
        assert_equal 0, T.must(alert_groups[1])[:count_high]
        assert_equal 0, T.must(alert_groups[1])[:count_medium]
        assert_equal 0, T.must(alert_groups[1])[:count_low]
        assert_equal 1, T.must(alert_groups[1])[:total]
      end
    end
  end
end
