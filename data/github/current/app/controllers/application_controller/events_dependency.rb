# typed: false
# frozen_string_literal: true

module ApplicationController::EventsDependency
  extend ActiveSupport::Concern

  included do
    helper_method :events_timeline
    helper_method :event_count
    helper_method :current_events
  end

  # Public
  def events_timeline
    @events_timeline ||= load_events_timeline
  end

  # Public
  def event_count
    @event_count ||= events_timeline.event_count
  end

  # Public
  def current_events
    @current_events ||= events_timeline.events(page: current_page)
  end

  # Public: A message to send in response to requests for deprecated timeline
  # endpoints.
  #
  # docs_url - The documentation URL for the deprecated API's replacement.
  #
  # Returns a Hash.
  def gone_payload(docs_url)
    message = "Hello there, wayfaring stranger. If you’re reading this then " \
    "you probably didn’t see our blog post a couple of years " \
    "back announcing that this API would go away: http://git.io/17AROg "\
    "Fear not, you should be able to get what you need from the shiny new " \
    "Events API instead."
    {
      message: message,
      documentation_url: docs_url,
    }
  end

  # Private: Load the given timeline from Stratocaster or Conduit.
  #
  # timeline - The String event timeline.
  #
  # Returns an Array of Stratocaster::Events or a Conduit::Web::Feed
  private

  def load_events_timeline(timeline_name = events_timeline_key)
    if use_conduit?
      return load_conduit_events(timeline_name)
    end

    load_stratocaster_events(timeline_name)
  end

  def load_stratocaster_events(timeline_name)
    normalized_name = normalize_stratocaster_timeline_key(timeline_name)
    timeline = Stratocaster::Timeline.for(normalized_name, current_user)

    if request.format && (request.format.atom? || request.format.json?)
      timeline.preload_events
    end

    timeline
  end

  # The ":private" suffix on timeline keys (e.g., "user:123:private") is a
  # Conduit-specific convention introduced for atom feed integration. Stratocaster
  # does not recognize this suffix and would classify the key as UNKNOWN, routing
  # it to an empty index. Stripping it maps the key back to "user:123" which
  # Stratocaster correctly handles as HOMEPAGE_ALL.
  def normalize_stratocaster_timeline_key(timeline_name)
    timeline_name.delete_suffix(":private")
  end

  def load_conduit_events(timeline_name)
    Conduit::Timeline.for(timeline_name, current_user, cap_filter:)
  end

  def use_conduit?
    GitHub.conduit_enabled?(user: current_user)
  end
end
