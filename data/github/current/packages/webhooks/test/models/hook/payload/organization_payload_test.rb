# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadOrganizationPayloadTest < GitHub::TestCase
  fixtures do
    @org_admin  = create(:user)
    @org        = create :organization, admin: @org_admin
    @user       = create(:user)
    @actor      = create(:user)
  end

  context "when an organization is created" do
    test "payload is complete" do
      event = Hook::Event::OrganizationEvent.new(
          organization_id: @org.id,
          actor_id: @actor.id,
          action: :created,
      )
      payload = Hook::Payload::OrganizationPayload.new(event).to_hash

      assert_equal :created, payload[:action]
      assert_equal @actor.login, payload[:sender][:login]
      assert_equal @org.login, payload[:organization][:login]
      assert_equal [:action, :organization, :sender], payload.keys.sort
    end
  end

  context "when a user is added to an organization" do
    test "payload is complete" do
      @org.add_member(@user, action: :admin)

      payload = build_hook_payload(
        action: :member_added,
        actor_id: @actor.id,
      ).to_hash

      assert_equal :member_added, payload[:action]
      assert_equal @actor.login, payload[:sender][:login]
      assert_equal @org.login, payload[:organization][:login]
      assert_equal @user.login, payload[:membership][:user][:login]
      assert_equal "admin", payload[:membership][:role]
      assert_equal "active", payload[:membership][:state]
      refute_includes payload[:membership].keys.map(&:to_sym), :organization
    end
  end

  context "when a member is removed from an organization" do
    test "payload is complete" do
      @org.remove_member!(@user)

      payload = build_hook_payload(
        action: :member_removed,
        actor_id: @actor.id,
      ).to_hash

      assert_equal :member_removed, payload[:action]
      assert_equal @actor.login, payload[:sender][:login]
      assert_equal @org.login, payload[:organization][:login]
      assert_equal @user.login, payload[:membership][:user][:login]
      assert_equal "unaffiliated", payload[:membership][:role]
      assert_equal "inactive", payload[:membership][:state]
      refute_includes payload[:membership].keys.map(&:to_sym), :organization
    end
  end

  context "when a user is invited to an organization" do
    test "payload is complete" do
      invitation = @org.invite(@user, inviter: @org_admin)

      payload = build_hook_payload(
        action: :member_invited,
        actor_id: @actor.id,
        organization_id: @org.id,
        invitation_id: invitation.id,
      ).to_hash

      assert_equal :member_invited, payload[:action]
      assert_equal @actor.login, payload[:sender][:login]
      assert_equal @org.login, payload[:organization][:login]
      assert_equal @user.login, payload[:invitation][:login]
      assert_equal "direct_member", payload[:invitation][:role]
      assert_equal @user.id, payload[:user][:id]
      refute_includes payload[:invitation].keys.map(&:to_sym), :organization
    end
  end

  context "when an email is invited to an organization" do
    test "payload is complete" do
      invitation = @org.invite(email: "barrack.obama@gmail.com", inviter: @org_admin)

      payload = build_hook_payload(
        action: :member_invited,
        actor_id: @actor.id,
        organization_id: @org.id,
        invitation_id: invitation.id,
      ).to_hash

      assert_equal :member_invited, payload[:action]
      assert_equal @actor.login, payload[:sender][:login]
      assert_equal @org.login, payload[:organization][:login]
      assert_equal "barrack.obama@gmail.com", payload[:invitation][:email]
      assert_equal "direct_member", payload[:invitation][:role]
      refute_includes payload[:invitation].keys.map(&:to_sym), :organization
    end
  end

  context "when an organization is renamed" do
    test "payload is complete" do
      event = Hook::Event::OrganizationEvent.new(
          organization_id: @org.id,
          actor_id: @actor.id,
          action: :renamed,
          changes: { old_login: "new-org" },
      )
      payload = Hook::Payload::OrganizationPayload.new(event).to_hash

      assert_equal :renamed, payload[:action]
      assert_equal @actor.login, payload[:sender][:login]
      assert_equal @org.login, payload[:organization][:login]
      assert_equal "new-org", payload.dig(:changes, :login, :from)
      assert_equal [:action, :changes, :organization, :sender], payload.keys.sort
    end
  end

  def build_hook_payload(attrs = {})
    defaults = {
      organization_id: @org.id,
      user_id: @user.id,
    }

    event = Hook::Event::OrganizationEvent.new(attrs.reverse_merge(defaults))
    Hook::Payload::OrganizationPayload.new(event)
  end
end
