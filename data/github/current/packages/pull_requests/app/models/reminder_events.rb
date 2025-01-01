# typed: false
# frozen_string_literal: true

module ReminderEvents
  extend ActiveSupport::Concern

  included do
    has_many :event_subscriptions, as: :subscriber, class_name: "ReminderEventSubscription", dependent: :destroy, autosave: true
    accepts_nested_attributes_for :event_subscriptions, allow_destroy: true

    # event_type is a string or symbol for the enum
    scope :for_event_type, ->(event_type) do
      event_type_db = ReminderEventSubscription.event_types[event_type]
      if event_type_db
        joins(:event_subscriptions).where(reminder_event_subscriptions: { event_type: event_type_db })
      else
        none
      end
    end
  end

  def event_subscriptions_attributes=(attributes)
    # Unassign event subscriptions that aren't persisted. This can happen when assigning times twice but not saving.
    # The assumption is that the latest should be the only one saved
    self.event_subscriptions = event_subscriptions.reject { |t| !t.persisted? }

    current_subscriptions = self.event_subscriptions.index_by(&:event_type)

    # Add IDs for any existing attributes.
    # This will make rails use the existing one instead of inserting/deleting old ones
    attributes = attributes.map do |new_subscription|
      key = new_subscription["event_type"]
      existing_subscription = current_subscriptions[key]
      next new_subscription unless existing_subscription

      new_subscription["id"] = existing_subscription.id
      current_subscriptions.delete(key)
      new_subscription
    end

    # Mark all remaining existing subscriptions as "marked for destruction".
    # This will make rails delete the now-unused records instead of keeping them around
    # Doc: https://api.rubyonrails.org/classes/ActiveRecord/NestedAttributes/ClassMethods.html#method-i-accepts_nested_attributes_for
    current_subscriptions.each do |_, subscription|
      attributes << { "id" => subscription.id, "_destroy" => true }
    end

    super(attributes)
  end

  def event_types=(types)
    attributes = types.map { |t| { "event_type" => t } }
    self.event_subscriptions_attributes = attributes
  end

  def event_types
    event_subscriptions.map(&:event_type)
  end

  def subscription_for_type(event_type)
    event_subscriptions.detect { |event_sub| event_sub.event_type == event_type.to_s }
  end
end
