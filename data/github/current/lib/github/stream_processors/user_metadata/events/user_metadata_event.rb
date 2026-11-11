# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      module Events
        class UserMetadataEvent
          RECALCULATION_SCHEMA = "github.user_metadata.v1.Recalculation"

          def self.schemas_for(processor)
            processor_class = GitHub::StreamProcessors::UserMetadata.const_get processor
            processor_class::DEFAULT_SUBSCRIBE_TO.without /#{RECALCULATION_SCHEMA}\Z/
          end

          USER_BEHAVIOR_SCHEMA = "github.v1.UserBehavior"
          MEMBERSHIP_UPDATE_SCHEMA = "github.v1.MembershipUpdate"
          DISCUSSION_COMMENT_SCHEMAS = %w(
            github.discussions.v1.DiscussionCommentMarkAsAnswer
            github.discussions.v1.DiscussionCommentUnmarkAsAnswer
          ).freeze
          ADVISORY_CREDIT_SCHEMAS = %w(
            github.security_advisories.v0.AdvisoryCreditCreate
            github.security_advisories.v0.AdvisoryCreditAccept
            github.security_advisories.v0.AdvisoryCreditDecline
            github.security_advisories.v0.AdvisoryCreditDestroy
          ).freeze
          PACKAGE_PUBLISH_SCHEMAS = %w(
            package_registry.v0.PackagePublished
            package_registry.v0.PackageDeleted
            registry_metadata.v0.PackagePublished
            registry_metadata.v0.PackageDeleted
            registry_metadata.v0.VersionPublished
          ).freeze
          PROJECT_EVENT_SCHEMA = "github.v1.ProjectEvent"
          REPOSITORY_EVENT_SCHEMAS = %w(
            github.v1.RepositoryArchivedStatusChanged
            github.v1.RepositoryCreate
            github.v1.RepositoryDeleted
            github.v1.RepositoryVisibilityChanged
            github.v1.RepositoryRestored
            github.v1.RepositoryTransfer
          ).freeze
          SPONSORSHIP_EVENT_SCHEMAS = schemas_for("SponsorProcessor")
          STAR_EVENT_SCHEMAS = %w(
            github.v1.RepositoryStar
            github.v1.TopicStar
          ).freeze
          USER_FOLLOW_SCHEMAS = %w(
            github.v1.UserFollow
            github.v1.UserUnfollow
          ).freeze
          ACHIEVEMENT_SCHEMA = "github.achievements.v1.AchievementUnlock"

          def self.from(message, processor)
            schema = message.schema.gsub(/\Ahydro\.schemas\./, "")
            case schema
            when *ADVISORY_CREDIT_SCHEMAS
              GlobalAdvisoryCreditEvent.new(message, processor)
            when *DISCUSSION_COMMENT_SCHEMAS
              DiscussionCommentMarkEvent.new(message, processor)
            when MEMBERSHIP_UPDATE_SCHEMA
              MembershipUpdateEvent.new(message, processor)
            when *PACKAGE_PUBLISH_SCHEMAS
              PackageEvent.new(message, processor)
            when PROJECT_EVENT_SCHEMA
              ProjectEvent.new(message, processor)
            when RECALCULATION_SCHEMA
              RecalculationEvent.new(message, processor)
            when *REPOSITORY_EVENT_SCHEMAS
              RepositoryEvent.new(message, processor)
            when *SPONSORSHIP_EVENT_SCHEMAS
              SponsorshipEvent.new(message, processor)
            when *STAR_EVENT_SCHEMAS
              StarEvent.new(message, processor)
            when USER_BEHAVIOR_SCHEMA
              UserBehaviorEvent.new(message, processor)
            when *USER_FOLLOW_SCHEMAS
              UserFollowEvent.new(message, processor)
            when ACHIEVEMENT_SCHEMA
              AchievementEvent.new(message, processor)
            else
              UnknownEvent.new(message, processor)
            end
          end

          attr_reader :message, :processor

          def initialize(message, processor)
            @message = message
            @processor = processor
          end

          def name
            self.class.name.gsub(/\A#{self.class.module_parent_name}::/, "")
          end

          def recalculation?
            false
          end

          def actors
            @actors ||= begin
              actor_id = message.value.dig(:actor, :id) || message.value.dig(:actor_id)
              with_read { User.where(id: actor_id) }
            end
          end

          private

          # Simple wrapper for connecting to read pool for read operations only.
          def with_read
            ActiveRecord::Base.connected_to(role: :reading) do
              yield
            end
          end
        end
      end
    end
  end
end
