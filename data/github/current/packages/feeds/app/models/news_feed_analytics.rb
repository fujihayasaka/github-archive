# typed: true
# frozen_string_literal: true

class NewsFeedAnalytics
  extend HydroHelper

  TARGET_TYPE_EVENT = "event"
  TARGET_TYPE_EVENT_GROUP = "event_group"

  # Internal: Data attributes for a news feed event click event
  #
  # event - an instance of Stratocaster::Event
  # target - the attributed item (i.e. "actor", "repo", "stargazers", etc)
  # event_details - Hash of event details
  #   additional_details_shown - true if additional event details are shown
  #   grouped - true if the event is part of an event group, false if a single event
  # org_id - the ID of the current organization if present
  # viewer_id - the ID of the current user if present
  #
  # Returns a hash with the keys "hydro-click", "hydro-click-hmac", and "ga-click"
  def self.event_click_attributes(event, target:, event_details: {}, org_id: nil, viewer_id: nil)
    hydro_click_dimensions(
      event: event,
      event_details: event_details,
      target: target,
      org_id: org_id,
      viewer_id: viewer_id,
      retrieved_id: event.retrieved_id,
    )
  end

  # Internal: Data attributes for a news feed event group click event
  #
  # event_group - Hash representing an event group
  #   quantity: Integer - The number of grouped events
  #   includes_viewer: Bool - Is the viewer the target of any grouped event
  #   type: The type of event in the group (e.g. FollowEvent, WatchEvent, etc)
  # org_id - the ID of the current organization if present
  # viewer_id - the ID of the current user if present
  #
  # Returns a hash with the keys "hydro-click", "hydro-click-hmac", and "ga-click"
  def self.event_group_click_attributes(event_group, org_id: nil, viewer_id: nil)
    hydro_click_dimensions(event_group: event_group, org_id: org_id,
                                              viewer_id: viewer_id)
  end

  # Internal: Data attributes for a news feed view event
  #
  # event - an instance of Stratocaster::Event
  # event_details - a Hash of event_details
  #   additional_details_shown - true if additional event details are shown
  #   grouped - true if the event is part of an event group
  # org_id - the ID of the current organization if present
  # viewer_id - the ID of the current user if present
  #
  # Returns a hash with the keys "hydro-view" and "hydro-view-hmac"
  def self.event_view_attributes(event, event_details: {}, org_id: nil, viewer_id: nil)
    hydro_view_dimensions(event: event, event_details: event_details, org_id: org_id,
                          viewer_id: viewer_id, retrieved_id: event.retrieved_id)
  end

  # Internal: Data attributes for a news feed view event
  #
  # event_group - Hash representing an event group
  #   quantity: Integer - The number of grouped events
  #   includes_viewer: Bool - Is the viewer the target of any grouped event
  #   type: The type of event in the group (e.g. FollowEvent, WatchEvent, etc)
  # org_id - the ID of the current organization if present
  # viewer_id - the ID of the current user if present
  #
  # Returns a hash with the keys "hydro-view" and "hydro-view-hmac"
  def self.event_group_view_attributes(event_group, org_id: nil, viewer_id: nil)
    hydro_view_dimensions(event_group: event_group, org_id: org_id, viewer_id: viewer_id)
  end

  def self.hydro_click_dimensions(**args)
    dimensions = base_dimensions(**args)
    hydro_click_tracking_attributes("news_feed.event.click", dimensions.merge(
      action_target: args[:target],
    ))
  end
  private_class_method :hydro_click_dimensions


  def self.hydro_view_dimensions(**args)
    dimensions = base_dimensions(**args)
    hydro_view_tracking_attributes("news_feed.event.view", dimensions)
  end
  private_class_method :hydro_view_dimensions

  def self.base_dimensions(**args)
    event         = args[:event]
    event_details = args[:event_details]
    org_id        = args[:org_id]
    viewer_id     = args[:viewer_id]
    event_group   = args[:event_group]
    retrieved_id  = args[:retrieved_id]
    target_type   = if event
      TARGET_TYPE_EVENT
    else
      TARGET_TYPE_EVENT_GROUP
    end

    {
      event: event && event.to_hydro.merge(event_details),
      event_group: event_group,
      org_id: org_id,
      target_type: target_type,
      user_id: viewer_id,
      feed_card: {
        card_retrieved_id: retrieved_id,
      },
    }
  end
  private_class_method :base_dimensions
end
