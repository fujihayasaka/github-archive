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

  # Private: Load the given timeline.  Also filters bad events and
  # preloads any associations to speed up rendering time.  If a user is
  # currently logged in, events by the actor are removed.
  #
  # timeline - The String event timeline.
  #
  # Returns an Array of Stratocaster::Events.
  private

  def load_events_timeline(timeline_name = events_timeline_key)
    timeline = Stratocaster::Timeline.for(timeline_name, current_user)

    if request.format && (request.format.atom? || request.format.json?)
      timeline.preload_events
    end

    timeline
  end
end
