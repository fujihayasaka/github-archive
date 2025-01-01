# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventLabelEventTest < GitHub::TestCase
  include HookEventTestHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user   = create(:user)
    @org    = create(:organization)
    @repo   = create :repository, owner: @org
    @label  = create :label, repository: @repo, name: "security"

    @event = Hook::Event::LabelEvent.new(
      action: :created,
      label_id: @label.id,
      actor_id: @user.id,
    )

    @event_with_changes = Hook::Event::LabelEvent.new(
      action: :created,
      label_id: @label.id,
      actor_id: @user.id,
      changes: {
        old_name: "old-name",
        old_color: "old-color",
        old_description: nil
      },
    )
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::LabelEvent, :action, :label_id
  end

  context "#label" do
    test "returns the specified label" do
      assert_equal @label, @event.label
    end
  end

  context "#target_repository" do
    test "returns the repository of the specified label" do
      assert_equal @repo, @event.target_repository
    end
  end

  context "#actor" do
    test "returns the user who created the label" do
      assert_equal @user, @event.actor
    end
  end

  context "#deliverable?" do
    test "returns false if the label is not found" do
      event = Hook::Event::LabelEvent.new(
        action: :created,
        label_id: -1,
        actor_id: @user.id,
      )

      refute_predicate event, :deliverable?
    end
  end

  context "#changes" do
    test "returns as a hash the fields from the changes attributes that are not nil" do
      expected_changes = {
        name: {
          from: "old-name",
        },
        color: {
          from: "old-color"
        },
      }

      assert_equal expected_changes, @event_with_changes.changes
    end

    test "returns nil when the event had no changes" do
      assert_nil @event.changes
    end
  end
end
