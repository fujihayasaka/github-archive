# typed: true
# frozen_string_literal: true

require "test_helper"

class OnboardingEventTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  setup do
    @event = build :onboarding_event, user: @user
  end

  context ".table_name" do
    test "is onboarding_events" do
      assert_equal "onboarding_events", Onboarding::Event.table_name
    end
  end

  context "validations" do
    test "requires a user" do
      @event.user_id = nil
      @event.valid?
      refute_empty @event.errors[:user_id], "user can't be blank"
    end

    test "requires a name" do
      @event.name = nil
      @event.valid?
      refute_empty @event.errors[:name], "name can't be blank"
    end

    test "name must be valid" do
      @event.name = "foobar"
      @event.valid?
      assert_equal ["is not included in the list"], @event.errors[:name]
    end
  end

  context "event instrumentation" do
    Onboarding::Event::VALID_EVENTS.each do |event_name|
      test "instruments 'onboarding.#{event_name}' events" do
        events = subscribe "onboarding.#{event_name}"

        onboarding_event = create :onboarding_event, user: @user, name: event_name

        expected_payload = {
          user: @user.login,
          user_id: @user.id,
          event: event_name,
        }
        assert event = events.pop, "expected an instrumentation event for onboarding.#{event_name}"
        assert_equal expected_payload, event.payload
      end
    end
  end
end
