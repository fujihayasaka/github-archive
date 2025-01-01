# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadLabelPayloadTest < GitHub::TestCase
  fixtures do
    @user   = create(:user)
    @repo   = create(:repository)
    @label  = create :label, repository: @repo, name: "front-end"
  end

  [:created, :deleted].each do |action|
    context "when a label is #{action}" do
      test "payload is complete" do
        payload = build_hook_payload(
          action: action,
          actor_id: @user.id,
        ).to_hash

        label_payload = payload[:label]

        assert_equal action, payload[:action]
        assert_equal @user.id, payload[:sender][:id]
        assert_equal @label.name, label_payload[:name]
        assert_equal @label.color, label_payload[:color]
      end
    end
  end

  context "when a label is edited" do
    test "payload is complete without changes" do
      payload = build_hook_payload(
        action: :edited,
        actor_id: @user.id,
      ).to_hash

      label_payload = payload[:label]

      assert_equal :edited, payload[:action]
      assert_equal @user.id, payload[:sender][:id]
      assert_equal @label.name, label_payload[:name]
      assert_equal @label.color, label_payload[:color]
      assert_nil payload[:changes]
    end

    test "payload is complete with changes" do
      changes = {
        old_name: "I used to have this name",
        old_color: "I used to have this color",
      }

      payload = build_hook_payload(
        action: :edited,
        actor_id: @user.id,
        changes: changes,
      ).to_hash

      label_payload = payload[:label]

      assert_equal :edited, payload[:action]
      assert_equal @user.id, payload[:sender][:id]
      assert_equal @label.name, label_payload[:name]
      assert_equal @label.color, label_payload[:color]
      assert payload[:changes].present?
    end
  end

  def build_hook_payload(attrs = {})
    defaults = {
      label_id: @label.id,
    }

    event = Hook::Event::LabelEvent.new(attrs.reverse_merge(defaults))
    Hook::Payload::LabelPayload.new(event)
  end
end
