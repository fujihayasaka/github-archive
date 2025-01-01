# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadMemberPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @actor = create(:user)
    @repo = create :repository, owner: @actor
  end

  [:added, :removed].each do |action|
    context "when the member is #{action}" do
      test "v3" do
        payload = build_member_payload(action: action)
        v3 = payload.to_hash

        assert_equal action, v3[:action]

        assert_equal @user.id, v3[:member][:id]
        assert_equal @user.login, v3[:member][:login]

        assert_equal @repo.id, v3[:repository][:id]
        assert_equal @repo.name, v3[:repository][:name]

        assert_equal @actor.id, v3[:sender][:id]
        assert_equal @actor.login, v3[:sender][:login]
      end
    end
  end

  context "when a member's permissions are updated" do
    test "v3" do
      changes = {
        old_permission: :admin,
        new_permission: :write,
      }
      payload = build_member_payload(action: :edited, changes: changes)
      v3 = payload.to_hash

      assert_equal :edited, v3[:action]
      assert_equal @user.id, v3[:member][:id]
      assert_includes v3, :changes
    end
  end

  def build_member_payload(attrs = {})
    default_attrs = {
      repo_id: @repo.id,
      user_id: @user.id,
      actor_id: @actor.id,
    }

    event = Hook::Event::MemberEvent.new(attrs.reverse_merge(default_attrs))
    Hook::Payload::MemberPayload.new(event)
  end
end
