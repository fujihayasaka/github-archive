# typed: true
# frozen_string_literal: true

require "test_helper"

class MembershipRelatedToTeamsTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @user2 = create(:user)
    @org  = create(:organization)
    @team = create(:team, organization: @org)
    @team.add_member(@user)
    @team.add_member(@user2)
  end

  context "#remove" do
    test "removes membership between a team and a user" do
      membership = Team::Membership.new(@team, @user.id, [], send_notification: false, team_destroyed: false)
      membership.remove(queue_delete_jobs: false)
      refute @team.member?(@user)
    end

    test "emits a needle when an ability fails to remove" do
      assert_raises StandardError do
        membership = Team::Membership.new(@team, @user.id, [], send_notification: false, team_destroyed: false)
        membership.remove(queue_delete_jobs: false) do
          raise StandardError.new "Let's force a needle"
        end
      end
      needle = Failbot.backend.reports.last
      assert_match /^Failed to revoke membership/, Failbot.exception_message_from_hash(needle)
    end

    test "Removing membership sends an email when the team isn't enterprise team managed" do
      business = create :business, organizations: [@org]
      membership = Team::Membership.new(@team, @user.id, [], send_notification: false, team_destroyed: false)
      membership.stubs(:send_removal_notification).once
      membership.remove(queue_delete_jobs: false)
    end

    test "Removing membership doesn't send an email when enterprise team managed" do
      business = create :business, organizations: [@org]
      @team.stubs(:enterprise_team_managed?).returns(true)
      membership = Team::Membership.new(@team, @user.id, [], send_notification: false, team_destroyed: false)
      membership.stubs(:send_removal_notification).never
      membership.remove(queue_delete_jobs: false, caller_type: :enterprise_team)
    end
  end

  context "#bulk_remove" do
    test "removes membership between a team and users" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      membership = Team::Membership.new(
        @team,
        [@user.id, @user2.id],
        [],
        send_notification: false,
        team_destroyed: false
      )
      membership.bulk_remove(users: [@user, @user2], queue_delete_jobs: false)
      refute @team.member?(@user)
      refute @team.member?(@user2)
    end

    test "emits a needle when an ability fails to remove" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      assert_raises StandardError do
        membership = Team::Membership.new(
          @team,
          [@user.id, @user2.id],
          [],
          send_notification: false,
          team_destroyed: false
        )
        Ability.stubs(:revoke_abilities).raises(StandardError.new "Let's force a needle")
        membership.bulk_remove(users: [@user, @user2], queue_delete_jobs: false)
      end
      needle = Failbot.backend.reports.last
      assert_match /^Failed to bulk revoke membership/, Failbot.exception_message_from_hash(needle)
    end

    test "Removing membership sends an email when the team isn't enterprise team managed" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      business = create :business, organizations: [@org]
      membership = Team::Membership.new(
        @team,
        [@user.id, @user2.id],
        [],
        send_notification: false,
        team_destroyed: false
      )
      membership.stubs(:send_removal_notification).twice
      membership.bulk_remove(users: [@user, @user2], queue_delete_jobs: false)
    end

    test "Removing membership doesn't send an email when enterprise team managed" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      business = create :business, organizations: [@org]
      @team.stubs(:enterprise_team_managed?).returns(true)
      membership = Team::Membership.new(
        @team,
        [@user.id, @user2.id],
        [],
        send_notification: false,
        team_destroyed: false
      )
      membership.stubs(:send_removal_notification).never
      membership.bulk_remove(users: [@user, @user2], queue_delete_jobs: false, caller_type: :enterprise_team)
    end
  end
end
