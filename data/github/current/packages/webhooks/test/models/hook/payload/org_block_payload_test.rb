# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadOrgBlockPayloadTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @owner        = create(:user)
    @org          = create :organization, admin: @owner
    @blocked_user = create(:user)
    @event        = Hook::Event::OrgBlockEvent.new({
                      org_id: @org.id,
                      actor_id: @owner.id,
                      blocked_user_id: @blocked_user.id,
                      action: :blocked,
                    })
    @payload      = Hook::Payload::OrgBlockPayload.new @event
    @v3           = @payload.to_hash
  end

  context "v3" do
    test "includes the action" do
      assert_equal :blocked, @v3[:action]
    end

    test "includes the org" do
      assert_equal @org.id, @v3[:organization][:id]
      assert_equal @org.login, @v3[:organization][:login]
    end

    test "includes the actor" do
      assert_equal @owner.id, @v3[:sender][:id]
      assert_equal @owner.login, @v3[:sender][:login]
    end

    test "includes the blocked user" do
      assert_equal @blocked_user.id, @v3[:blocked_user][:id]
      assert_equal @blocked_user.login, @v3[:blocked_user][:login]
    end
  end
end
