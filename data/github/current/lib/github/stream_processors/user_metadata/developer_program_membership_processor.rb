# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      class DeveloperProgramMembershipProcessor < UserMetadataBaseProcessor
        HYDRO_TARGET_PROCESSOR_NAME = :DEVELOPER_PROGRAM_MEMBERSHIP.freeze
        DEFAULT_GROUP_ID = "developer_program_membership_processor"
        DEFAULT_SUBSCRIBE_TO = [/github.user_metadata.v1.Recalculation\Z/].freeze

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.metric_prefix = "user_metadata_processor.developer_program_membership"
          self.dead_letter_topic = "user_metadata.v0.DeveloperProgramMembership.DeadLetter"
        end

        # Public: User metadata that this stream processor should update for a given user.
        #
        # event - the UserMetadataEvent currently being processed
        # user  - a User with metadata affected by the event being processed
        #
        # Returns a Hash of metadata key/value pairs to update for the specified user.
        def metadata_updates(event, user)
          {
            is_developer_program_member: is_developer_program_member?(user)
          }
        end

        private

        def is_developer_program_member?(user)
          with_read { !!user.developer_program_member? }
        end
      end
    end
  end
end
