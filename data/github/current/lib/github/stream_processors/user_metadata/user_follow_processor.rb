# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      class UserFollowProcessor < UserMetadataBaseProcessor
        HYDRO_TARGET_PROCESSOR_NAME = :FOLLOWS.freeze
        DEFAULT_GROUP_ID = "user_follow_processor"
        DEFAULT_SUBSCRIBE_TO = [
          /github.v1.UserFollow\Z/,
          /github.v1.UserUnfollow\Z/,
          /github.user_metadata.v1.Recalculation\Z/,
        ]

        # Since we're querying for existing followers direclty from the user associations,
        # this processor can be exempt from the tenant context requirement.
        exempt_from_tenant_context_requirement

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.metric_prefix = "user_metadata_processor.user_follow"
          self.dead_letter_topic = "user_metadata.v0.UserFollow.DeadLetter"
        end

        private

        # Public: User metadata that this stream processor should update for a given user.
        #
        # event - the UserMetadataEvent currently being processed
        # user  - a User with metadata affected by the event being processed
        #
        # Returns a Hash of metadata key/value pairs to update for the specified user.
        def metadata_updates(event, user)
          with_read do
            if event.recalculation?
              follower_metadata(user).merge(followee_metadata(user))
            elsif event.user_is_follower?(user)
              follower_metadata(user)
            elsif event.user_is_followee?(user)
              followee_metadata(user)
            end
          end
        end

        def follower_metadata(user)
          {
            following_count: user.following_count!,
          }
        end

        def followee_metadata(user)
          {
            followers_count: user.followers_count!,
          }
        end
      end
    end
  end
end
