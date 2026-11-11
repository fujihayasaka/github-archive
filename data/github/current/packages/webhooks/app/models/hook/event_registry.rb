# typed: true
# frozen_string_literal: true

module Hook::EventRegistry
  extend self

  attr_reader :event_classes

  # Private: Registers a given Hook::Event subclass. This
  # is automatically called whenever a class inherits from
  # Hook::Event.
  def register(event_class)
    (@event_classes ||= Set.new) << event_class
  end

  # Public: Filters a set of events to only those visible by
  # the current user. Visibility is determined by an optional
  # feature flag name which may be defined on the event.
  #
  # event_classes - An array of Hook::Event classes.
  # user - A User object, most likely current_user.
  #
  # Returns an array of Hook::Event classes.
  def visible_to_user(event_classes, user)
    event_classes.select do |event_class|
      if event_class.feature_flagged?
        if event_class.flagged_actions.present?
          true
        else
          event_class.feature_flag_enabled_for(user)
        end
      else
        true
      end
    end
  end

  # Public: Returns a list of Hook::Event classes that are subscribable
  # by the given hook and optionally a user.
  #
  # hook - The Hook to get supported, subscribable events for.
  # user - (Optional) A User to scope the available events for.
  #
  # Returns an Array of Hook::Event classes.
  def subscribable_by(hook:, user: nil)
    target = hook.installation_target
    events = for_target(target).reject(&:auto_subscribed?)
    events = events.select { |event| event.visible_for?(user, target) }
    events
  end

  # Public: Returns a list of Hook::Event classes that support firing
  # on the given target.
  #
  # target - The target instance or class to get supported events for.
  #
  # Returns an Array of Hook::Event classes.
  def for_target(target)
    self.event_classes.select do |event|
      event.supports_target?(target)
    end
  end

  # Public: Fetches a list of all registered event types.
  #
  # Returns an Array of event type Strings
  def event_types
    event_classes.map(&:event_type)
  end

  # Public: Looks up a Hook::Event class by its event_type
  #
  # event_type - The String or Symbol event type
  #
  # Returns a Hook::Event class or nil
  def for_event_type(event_type)
    event_classes.find { |event_class| event_class.event_type == event_type.to_s }
  end
end
