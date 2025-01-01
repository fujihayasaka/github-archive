# typed: true
# frozen_string_literal: true
require "test_helper"

class ReminderEventSubscriptionTest < GitHub::TestCase
  context "#options_includes?" do
    test "matches case insensitive" do
      reminder = create(:personal_reminder, event_types: [:pull_request_labeled])
      subscription = reminder.subscription_for_type(:pull_request_labeled)
      subscription.update!(options: "bUg,happy")

      assert subscription.options_includes?("bug")
      assert subscription.options_includes?("buG")
      assert subscription.options_includes?("bUg")
      assert subscription.options_includes?("happy")
    end

    test "requires complete match" do
      reminder = create(:personal_reminder, event_types: [:pull_request_labeled])
      subscription = reminder.subscription_for_type(:pull_request_labeled)
      subscription.update!(options: "bUg,happy")

      refute subscription.options_includes?("happ")
    end
  end

  context "#options" do
    test "validates maximum size" do
      # Big options argument
      options = 1000.times.map { |n| "option-#{n}" }.join(",")

      reminder = create(:personal_reminder, event_types: %i[check_failure])
      subscription = reminder.subscription_for_type(:check_failure)

      refute subscription.update(options: options)
      refute subscription.valid?
      assert subscription.errors[:options]
    end
  end
end
