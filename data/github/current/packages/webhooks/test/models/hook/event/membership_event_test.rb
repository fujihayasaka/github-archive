# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventMembershipEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @actor = create(:user)
    @org = create :organization, admin: @actor
    @team = create(:team, organization: @org)

    @user = create(:user)
    @attrs = { member_id: @user.id,
               member_login: "user123",
               actor_id: @actor.id,
               organization_id: @org.id,
               action: :added }
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::MembershipEvent, :member_id, :member_login, :action, :organization_id
  end

  context "#target_organization" do
    test "returns the specified org" do
      event = Hook::Event::MembershipEvent.new @attrs
      assert_equal @org, event.target_organization
    end

    test "returns nil if the org seems to be deleted" do
      event = Hook::Event::MembershipEvent.new @attrs.merge(action: :removed, organization_id: -1)
      assert_nil event.target_organization
      assert event.target_organization_deleted?

      # We can't even attempt delivery here since the hooks have been deleted too.
      refute event.deliverable?
    end

    test "raises an exception if org is not found and we weren't expecting it to be delted" do
      event = Hook::Event::MembershipEvent.new @attrs.merge(action: :added, organization_id: -1)
      assert_raises ActiveRecord::RecordNotFound do
        event.target_organization
      end
    end
  end

  context "#team" do
    test "returns the team if specified" do
      event = Hook::Event::MembershipEvent.new @attrs.merge(team_id: @team.id)
      assert_equal @team, event.team
      refute event.team_deleted?
    end

    test "returns nil if not team is specified" do
      event = Hook::Event::MembershipEvent.new @attrs.merge(team_id: nil)
      assert_nil event.team
      refute event.team_deleted?
    end

    test "returns nil if the team seems to be deleted" do
      event = Hook::Event::MembershipEvent.new @attrs.merge(action: :removed, team_id: -1)
      assert_nil event.team
      assert event.team_deleted?
    end

    test "raises an exception if team is not found and we weren't expecting it to be delted" do
      event = Hook::Event::MembershipEvent.new @attrs.merge(action: :added, team_id: -1)
      assert_raises ActiveRecord::RecordNotFound do
        event.team
      end
    end
  end

  context "#member" do
    test "returns the specified member" do
      event = Hook::Event::MembershipEvent.new @attrs
      assert_equal @user, event.member
      refute event.member_deleted?
    end

    test "returns nil if the member seems to be deleted" do
      event = Hook::Event::MembershipEvent.new @attrs.merge(action: :removed, member_id: -1)
      assert_nil event.member
      assert event.member_deleted?
    end

    test "raises an exception if member is not found and we weren't expecting it to be delted" do
      event = Hook::Event::MembershipEvent.new @attrs.merge(action: :added, member_id: -1)
      assert_raises ActiveRecord::RecordNotFound do
        event.member
      end
    end
  end

  context "#actor" do
    test "returns the specified actor" do
      event = Hook::Event::MembershipEvent.new @attrs
      assert_equal @actor, event.actor
    end

    test "defaults to the organization if no actor is specified" do
      event = Hook::Event::MembershipEvent.new @attrs.merge(actor_id: nil)
      assert_equal @org, event.actor
    end

    test "returns nil if the actor seems to have deleted their own account" do
      event = Hook::Event::MembershipEvent.new @attrs.merge(action: :removed, member_id: -1, actor_id: -1)
      assert_nil event.actor
      assert event.member_deleted_own_account?
    end

    test "raises an exception if actor is not found and it doesn't look like they deleted their own account" do
      event = Hook::Event::MembershipEvent.new @attrs.merge(action: :removed, member_id: @user.id, actor_id: -1)
      assert_raises ActiveRecord::RecordNotFound do
        event.actor
      end
    end

    test "raises an exception if actor seems to have deleted their own account but the membership was not removed" do
      event = Hook::Event::MembershipEvent.new @attrs.merge(action: :added, member_id: -1, actor_id: -1)
      assert_raises ActiveRecord::RecordNotFound do
        event.actor
      end
    end
  end

  context "#action" do
    test "always returns a symbol" do
      event = Hook::Event::MembershipEvent.new @attrs.merge(action: "added")
      assert_equal :added, event.action
    end
  end

  context "#scope" do
    test "returns :team if a team was specified" do
      event = Hook::Event::MembershipEvent.new @attrs.merge(team_id: @team.id)
      assert_equal :team, event.scope
    end

    test "returns :organization if NO team was specified" do
      event = Hook::Event::MembershipEvent.new @attrs
      assert_equal :organization, event.scope
    end
  end
end
