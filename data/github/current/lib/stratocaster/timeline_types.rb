# typed: true
# frozen_string_literal: true

module Stratocaster
  module TimelineTypes

    GLOBAL          = "global".freeze
    ACTIVITY_PUBLIC = "activity_public".freeze
    ACTIVITY_ALL    = "activity_all".freeze
    HOMEPAGE_PUBLIC = "homepage_public".freeze
    HOMEPAGE_ALL    = "homepage_all".freeze
    REPO_ISSUES     = "repo_issues".freeze
    REPO            = "repo".freeze
    NETWORK         = "network".freeze
    ORG             = "org".freeze
    ORG_ALL         = "org_all".freeze
    UNKNOWN         = "unknown".freeze
    USER_RECEIVED_EVENTS = "received_events".freeze

    CHUNK_PUBLIC      = "public".freeze
    CHUNK_ACTOR       = "actor".freeze
    CHUNK_USER        = "user".freeze
    CHUNK_REPO        = REPO
    CHUNK_ISSUES      = "issues".freeze
    CHUNK_NETWORK     = NETWORK
    CHUNK_ORG         = ORG
    CHUNK_RECEIVED_EVENTS = USER_RECEIVED_EVENTS

    ELIGIBLE_FOR_FANOUT = [
      CHUNK_PUBLIC,
      CHUNK_ACTOR,
      REPO,
      NETWORK,
      ORG,
      ORG_ALL,
      HOMEPAGE_PUBLIC,
      HOMEPAGE_ALL,
    ].freeze

    # Public
    #
    # Convert the given org_all_timeline (which is assumed to be
    # something like org:111111) to an org timeline (org:111111:public)
    #
    # Return String
    #
    def self.convert_org_all_to_org(org_all_key)
      "#{org_all_key}:public"
    end

    # Public
    #
    # Convert the given homepage_all_timeline (which is assumed to be
    # something like user:111111) to a homepage_public timeline (user:111111:public)
    #
    # Return String
    #
    def self.convert_homepage_all_to_homepage_public(homepage_all_key)
      "#{homepage_all_key}:public"
    end

    # Public
    #
    # Convert the given user_received_events_timeline (which is assumed to be
    # something like user:111111:received_events) to a homepage_all_timeline (user:111111)
    #
    # Return String
    #
    def self.convert_user_received_events_timeline_to_homepage_all(user_received_events_key)
      key_chunks = user_received_events_key.split(":")
      user_chunk = key_chunks[0]
      user_id_chunk = key_chunks[1]

      unless key_chunks[2].nil?
        GitHub.dogstats.increment("stratocaster.converted_timeline", tags: ["timeline_type:#{key_chunks[2]}"])
      end

      [user_chunk, user_id_chunk].join(":")
    end

    # Public
    #
    # Does the given timeline correspond to an org_all timeline?
    #
    # Return Boolean
    #
    def self.org_all_timeline?(timeline)
      self.type_for(timeline) == TimelineTypes::ORG_ALL
    end

    # Public
    #
    # Does the given timeline correspond to an homepage_all timeline?
    #
    # Return Boolean
    #
    def self.homepage_all_timeline?(timeline)
      self.type_for(timeline) == TimelineTypes::HOMEPAGE_ALL
    end

    # Public
    #
    # Does the given timeline correspond to a user_received_events timeline?
    #
    # Return Boolean
    #
    def self.user_received_events_timeline?(timeline)
      self.type_for(timeline) == TimelineTypes::USER_RECEIVED_EVENTS
    end

    # Public
    #
    # Given a set of timelines, it returns a hash, where the keys are
    # the different timeline types, and the values are the timelines of
    # that type.
    #
    # Keys for types with no timelines are not returned.
    #
    # Return Hash<String, [String]>
    #
    def self.group(timelines)
      groups = {}
      timelines.each do |timeline|
        timeline = timeline.to_s
        type = type_for(timeline)
        (groups[type] ||= []) << timeline
      end
      groups
    end

    # Public
    #
    # Given the key for a certain timeline (without the stratocaster prefix)
    # This method returns it's type.
    #
    # Types for some example keys follows:
    #  {"public"                 => "global",
    #   "actor:111111:public"    => "activity_public",
    #   "actor:111111"           => "activity_all",
    #   "user:111111:public"     => "homepage_public",
    #   "user:111111"            => "homepage_all",
    #   "repo:111111"            => "repo",
    #   "repo:111111:issues"     => "repo_issues",
    #   "network:1111111:public" => "network",
    #   "org:111111:public"      => "org",
    #   "org:111111"             => "org_all" }
    #
    # Returns String
    #
    def self.type_for(timeline)
      chunks = timeline.to_s.split(":")
      case chunks[0]
      when CHUNK_PUBLIC
        GLOBAL
      when CHUNK_ACTOR
        case chunks[2]
        when CHUNK_PUBLIC
          ACTIVITY_PUBLIC
        when nil
          ACTIVITY_ALL
        else
          UNKNOWN
        end
      when CHUNK_USER
        case chunks[2]
        when CHUNK_PUBLIC
          HOMEPAGE_PUBLIC
        when CHUNK_RECEIVED_EVENTS
          USER_RECEIVED_EVENTS
        when nil
          HOMEPAGE_ALL
        else
          UNKNOWN
        end
      when CHUNK_REPO
        case chunks[2]
        when CHUNK_ISSUES
          REPO_ISSUES
        when nil
          REPO
        else
          UNKNOWN
        end
      when CHUNK_NETWORK
        NETWORK
      when CHUNK_ORG
        case chunks[2]
        when CHUNK_PUBLIC
          ORG
        else
          ORG_ALL
        end
      else
        UNKNOWN
      end
    end
  end
end
