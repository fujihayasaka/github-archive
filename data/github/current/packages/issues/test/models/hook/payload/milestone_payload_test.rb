# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadMilestonePayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user
    @milestone = create :milestone, repository: @repo, created_by: @repo.owner
  end

  [:created, :closed, :opened, :deleted].each do |action|
    context "when the Milestone is #{action}" do
      test "v3" do
        payload = build_milestone_payload(action: action)
        v3 = payload.to_hash

        assert_equal action, v3[:action]
        assert_equal @milestone.id, v3[:milestone][:id]
        assert_equal @repo.id, v3[:repository][:id]
        assert_equal @repo.name, v3[:repository][:name]
        assert_equal @user.id, v3[:sender][:id]
        assert_equal @user.login, v3[:sender][:login]
      end
    end
  end

  context "when a Milestone's attributes are updated" do
    test "v3" do
      changes = {
        old_description: "Changed Description",
        old_due_on: Time.now + 1.week,
        old_title: "Changed Title",
      }
      payload = build_milestone_payload(action: :edited, changes: changes)
      v3 = payload.to_hash

      assert_equal :edited, v3[:action]
      assert_equal @milestone.id, v3[:milestone][:id]
      assert_includes v3, :changes
    end
  end

  def build_milestone_payload(attrs = {})
    default_attrs = {
      milestone_id: @milestone.id,
      actor_id: @user.id,
    }

    event = Hook::Event::MilestoneEvent.new(attrs.reverse_merge(default_attrs))
    Hook::Payload::MilestonePayload.new(event)
  end
end
