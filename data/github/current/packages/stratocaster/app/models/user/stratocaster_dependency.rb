# typed: false
# frozen_string_literal: true

module User::StratocasterDependency
  extend ActiveSupport::Concern
  include GitHub::Memoizer
  include Stratocaster::EventTarget

  # Public: Generates the Stratocaster event key for a User
  #
  # :type  - A Symbol identifying a sub type, or nil.
  #          :actor                - The private feed of actions this user did.
  #          :actor_public         - The public feed of actions this user did.
  #          :user_public          - The public feed of actions this user is watching.
  #          :user_received_events - The private feed of actions this user is watching,
  #                                  surfaced in the GET /users/:user_id/received_events API endpoint.
  #          :org          - The private feed of organization actions.  Requires
  #                          a :param option.
  # :param - Provides more context for a feed type.  The :org type needs an
  #          Organization.
  #
  # Returns a String key.
  def events_key(options = {})
    type = options[:type] || :actor
    case type
    when :actor then "actor:#{id}"
    when :actor_public then "actor:#{id}:public"
    when :user_public then "user:#{id}:public"
    when :user then "user:#{id}"
    when :user_received_events then "user:#{id}:received_events"
    when :org
      param = options[:param]
      if !param.is_a?(Organization)
        raise ArgumentError, "Need a valid Organization :param: #{options.inspect}"
      end
      "org:#{param.id}"
    end
  end

  # Public: Clear a user's public and private activity
  #
  # Returns true if successful
  def clear_all_timelines
    user_timeline = events_key(type: :user)
    user_public_timeline = events_key(type: :user_public)
    GitHub.stratocaster.clear_timelines(user_timeline, user_public_timeline)
    instrument(:clear_all_timelines)

    true
  end

  def stratocaster_event_timestamp_cache_key
    "user.last-stratocaster-event-timestamp.#{self.id}"
  end
end
