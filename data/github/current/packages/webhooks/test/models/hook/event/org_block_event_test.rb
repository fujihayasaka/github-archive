# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventOrgBlockEventTest < GitHub::TestCase
  include HookEventTestHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @owner        = create(:user)
    @org          = create :organization, admin: @owner
    @blocked_user = create(:user)
    @event        = Hook::Event::OrgBlockEvent.new({
                      action: "block",
                      org_id: @org.id,
                      actor_id: @owner.id,
                      blocked_user_id: @blocked_user.id,
                    })
  end

  if !GitHub.user_abuse_mitigation_enabled?
    test "is unavailable" do
      refute Hook::Event::OrgBlockEvent.supported_targets.any?
    end
  end

  context "required attributes" do
    test "org_id is required" do
      assert_event_required_attributes Hook::Event::OrgBlockEvent, :org_id
    end

    test "blocked_user_id is required" do
      assert_event_required_attributes Hook::Event::OrgBlockEvent, :blocked_user_id
    end

    test "actor_id is required" do
      assert_event_required_attributes Hook::Event::OrgBlockEvent, :actor_id
    end

    test "action is required" do
      assert_event_required_attributes Hook::Event::OrgBlockEvent, :action
    end
  end

  context "helpers" do
    test "returns the target_organization" do
      assert_equal @org, @event.target_organization
    end

    test "returns the actor" do
      assert_equal @owner, @event.actor
    end

    test "returns the blocked user" do
      assert_equal @blocked_user, @event.blocked_user
    end
  end
end
