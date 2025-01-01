# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventSponsorshipEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @sponsorship = create(:sponsorship)
    @actor = create(:user)
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::SponsorshipEvent, :action, :sponsorship_id, :actor_id
  end

  context "#sponsorship" do
    test "returns the specified Sponsorship" do
      event = Hook::Event::SponsorshipEvent.new(
        action: :created,
        sponsorship_id: @sponsorship.id,
        actor_id: @actor.id,
        current_tier_id: @sponsorship.subscribable_id,
      )

      assert_equal @sponsorship, event.sponsorship
    end
  end

  context "#actor" do
    test "returns the specified User" do
      event = Hook::Event::SponsorshipEvent.new(
        action: :created,
        sponsorship_id: @sponsorship.id,
        actor_id: @actor.id,
        current_tier_id: @sponsorship.subscribable_id,
      )

      assert_equal @actor, event.actor
    end
  end
end
