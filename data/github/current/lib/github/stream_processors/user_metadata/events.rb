# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      module Events
        autoload :UserMetadataEvent, "github/stream_processors/user_metadata/events/user_metadata_event"

        autoload :AchievementEvent, "github/stream_processors/user_metadata/events/achievement_event"
        autoload :DiscussionCommentMarkEvent, "github/stream_processors/user_metadata/events/discussion_comment_mark_event"
        autoload :GlobalAdvisoryCreditEvent, "github/stream_processors/user_metadata/events/global_advisory_credit_event"
        autoload :MembershipUpdateEvent, "github/stream_processors/user_metadata/events/membership_update_event"
        autoload :PackageEvent, "github/stream_processors/user_metadata/events/package_event"
        autoload :ProjectEvent, "github/stream_processors/user_metadata/events/project_event"
        autoload :RecalculationEvent, "github/stream_processors/user_metadata/events/recalculation_event"
        autoload :RepositoryEvent, "github/stream_processors/user_metadata/events/repository_event"
        autoload :SponsorshipEvent, "github/stream_processors/user_metadata/events/sponsorship_event"
        autoload :StarEvent, "github/stream_processors/user_metadata/events/star_event"
        autoload :UnknownEvent, "github/stream_processors/user_metadata/events/unknown_event"
        autoload :UserBehaviorEvent, "github/stream_processors/user_metadata/events/user_behavior_event"
        autoload :UserFollowEvent, "github/stream_processors/user_metadata/events/user_follow_event"
      end
    end
  end
end
