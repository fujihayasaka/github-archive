# typed: true
# frozen_string_literal: true

class HookEventSubscription < ApplicationRecord::Domain::Hooks
  extend T::Helpers
  # Module which can be used to extend the association proxy in order to
  # provide some serializable-like methods.
  #
  # This allows you to treat the collection as a serialized Array of events.
  # The backing records will be persisted/destroyed when the parent is saved.
  #
  # Example:
  #
  #   has_many :hook_event_subscriptions,
  #     :autosave => true,
  #     :extend => HookEventSubscription::AssociationExtension
  #
  #   instance.hook_event_subscriptions.names
  #   # => ["issues", "pull_request"]
  #
  #   instance.hook_event_subscriptions.names = ["issues"]
  #   # => ["issues"]
  #   instance.save
  #   instance.hook_event_subscriptions.all
  #   # => [#<HookEventSubscription name: "issues">]
  #
  module AssociationExtension
    include Kernel
    # Public: Returns event names currently subscribed to by the subscriber
    # excluding any events which are currently marked for removal.
    #
    # Returns an Array of event names.
    def names
      active_events = T.unsafe(self).reject(&:marked_for_destruction?)
      active_events.map(&:name).freeze
    end

    # Public: Sets the subscriber's desired event subscriptions. Any existing
    # subscriptions not included will be marked for removal and destroyed when
    # the subscriber is saved.
    #
    # names - An Array of event names to subscribe to.
    #
    # Returns the subscribed Array of event names.
    def names=(event_names)
      event_names = Array(event_names).map(&:to_s).uniq

      existing_events = names
      events_to_add = event_names - existing_events
      events_to_remove = existing_events - event_names

      events_to_add.each do |name|
        event_to_unremove = T.unsafe(self).detect do |record|
          record.marked_for_destruction? && record.name == name
        end
        if event_to_unremove
          if event_to_unremove.persisted?
            event_to_unremove.reload
          else
            T.unsafe(self).build name: name
          end
        else
          T.unsafe(self).build name: name
        end
      end

      events_to_remove.each do |name|
        event_to_remove = T.unsafe(self).detect { |record| record.name == name }
        event_to_remove.mark_for_destruction
      end

      event_names
    end
  end

  belongs_to :subscriber, polymorphic: true
  destroy_in_background_with :subscriber, polymorphic_class_name: "Hook"
  destroy_in_background_with :subscriber, polymorphic_class_name: "IntegrationInstallation"
  destroy_in_background_with :subscriber, polymorphic_class_name: "IntegrationVersion"

  # Public: String name of the event type (e.g., "push", "issue_comment").
  # column :name

  validates_uniqueness_of :name, scope: [:subscriber_id, :subscriber_type], case_sensitive: false
  validate :event_name_in_registry

  scope :with_name_and_subscriber, lambda { |name, type, id|
    where(name: name, subscriber_type: type).where(subscriber_id: id)
  }

  # Internal
  def event_name_in_registry
    unless [Hook::WildcardEvent, *Hook::EventRegistry.event_types].include?(name.to_s)
      errors.add(:name, "Name must be a valid event name")
    end
  end
end
