# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventSubscriptionTest < GitHub::TestCase
  context "validates" do
    test "event name is valid" do
      subscriber = create(:hook, :org)

      subscription = HookEventSubscription.create(
        subscriber: subscriber,
        name: "issues",
      )
      assert_predicate subscription, :valid?

      invalid_subscription = HookEventSubscription.create(
        subscriber: subscriber,
        name: "not_an_event",
      )
      refute_predicate invalid_subscription, :valid?
      refute_empty invalid_subscription.errors[:name]
    end

    test "uniqueness of event name per subscriber" do
      subscriber = create(:hook, :org)

      subscription = HookEventSubscription.create(
        subscriber: subscriber,
        name: "issues",
      )

      dupe = HookEventSubscription.create(
        subscriber: subscriber,
        name: "issues",
      )

      refute_predicate dupe, :valid?
      refute_empty dupe.errors[:name]
    end
  end
end
