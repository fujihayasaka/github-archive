# typed: true
# frozen_string_literal: true


module Stratocaster
  autoload :Attributes, "stratocaster/attributes"
  autoload :Dispatcher, "stratocaster/dispatcher"
  autoload :DogstatsTags, "stratocaster/dogstats_tags"
  autoload :Error, "stratocaster/error"
  autoload :Event, "stratocaster/event"
  autoload :EventPayload, "stratocaster/event_payload"
  autoload :EventTypeActor, "stratocaster/event_type_actor"
  autoload :Fanout, "stratocaster/fanout"
  autoload :Filters, "stratocaster/filters"
  autoload :HelperMethods, "stratocaster/helper_methods"
  autoload :HomepageAllTimeline, "stratocaster/homepage_all_timeline"
  autoload :Indexers, "stratocaster/indexers"
  autoload :MemoryStore, "stratocaster/memory_store"
  autoload :Octolytics, "stratocaster/octolytics"
  autoload :OrgAllTimeline, "stratocaster/org_all_timeline"
  autoload :RefType, "stratocaster/ref_type"
  autoload :Response, "stratocaster/response"
  autoload :Service, "stratocaster/service"
  autoload :Mysql2Store, "stratocaster/mysql2_store"
  autoload :Timeline, "stratocaster/timeline"
  autoload :TimelineTypes, "stratocaster/timeline_types"
  autoload :UserReceivedEventsTimeline, "stratocaster/user_received_events_timeline"

  EVENT = "Event".freeze unless const_defined?(:EVENT)
  DEFAULT_INDEX_SIZE = 300
  DEFAULT_PAGE_SIZE = 30

  TIMELINE_UPDATE_SCHEMA = "github.v1.StratocasterTimelineUpdate".freeze
  REVIEW_LAB_TIMELINE_TOPIC = "review-lab.v1.StratocasterTimelineUpdate".freeze

  # Public
  #
  # event_type - string (e.g. "WatchEvent")
  #
  # Return Stratocaster::Attributes class name
  def self.attributes_class_for(event_type)
    return if event_type.blank?
    "::Stratocaster::Attributes::#{event_type.to_s.chomp(EVENT)}".constantize
  end
end
