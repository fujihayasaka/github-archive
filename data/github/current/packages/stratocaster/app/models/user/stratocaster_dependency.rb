# typed: false
# frozen_string_literal: true

require "explore_feed/feeds/kv"

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

  # Public: The last time the user has performed an action within GitHub that
  # generated a Stratocaster event.
  #
  # Returns ActiveSupport::TimeWithZone
  memoize def last_stratocaster_event_at
    if GitHub.stratocaster_event_timestamp_cache_enabled? &&
      cached_last_event_at = Feeds::KV.store.get(stratocaster_event_timestamp_cache_key).value { nil }
      Time.parse(cached_last_event_at).in_time_zone
    else
      recent_event_id = Stratocaster::Response.new { GitHub.stratocaster.ids(events_key) }.items.first
      event = GitHub.stratocaster.get(recent_event_id) if recent_event_id
      event.created_at.in_time_zone if event
    end
  end

  def stratocaster_event_timestamp_cache_key
    "user.last-stratocaster-event-timestamp.#{self.id}"
  end
end
