# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadMembershipPayloadTest < GitHub::TestCase
  fixtures do
    @actor = create(:user)
    @org = create :organization, admin: @actor
    @team = create(:team, organization: @org)
    @user = create(:user)
  end

  setup do
    @org_membership_event = Hook::Event::MembershipEvent.new member_id: @user.id,
      member_login: "user123",
      actor_id: @actor.id,
      organization_id: @org.id,
      action: :added
    @org_membership_payload = Hook::Payload::MembershipPayload.new @org_membership_event

    @team_membership_event = Hook::Event::MembershipEvent.new member_id: @user.id,
      member_login: "user123",
      actor_id: @actor.id,
      organization_id: @org.id,
      team_id: @team.id,
      action: :removed
    @team_membership_payload = Hook::Payload::MembershipPayload.new @team_membership_event
  end

  context "#v3" do
    test "for org membership payloads" do
      v3 = @org_membership_payload.to_hash

      assert_equal :added, v3[:action]
      assert_equal :organization, v3[:scope]

      assert_equal @user.id, v3[:member][:id]
      assert_equal @user.login, v3[:member][:login]

      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]

      refute v3.key?(:team), "Team key should not be included for org membership payloads"
    end

    test "for team membership payloads" do
      v3 = @team_membership_payload.to_hash

      assert_equal :removed, v3[:action]
      assert_equal :team, v3[:scope]

      assert_equal @user.id, v3[:member][:id]
      assert_equal @user.login, v3[:member][:login]

      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]

      assert_equal @team.id, v3[:team][:id]
    end
  end

end
