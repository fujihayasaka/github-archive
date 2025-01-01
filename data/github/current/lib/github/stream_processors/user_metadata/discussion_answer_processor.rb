# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      class DiscussionAnswerProcessor < UserMetadataBaseProcessor
        HYDRO_TARGET_PROCESSOR_NAME = :DISCUSSION_ANSWERS.freeze
        DEFAULT_GROUP_ID = "discussion_answer_processor"
        DEFAULT_SUBSCRIBE_TO = [
          /github.discussions.v1.DiscussionCommentMarkAsAnswer\Z/,
          /github.discussions.v1.DiscussionCommentUnmarkAsAnswer\Z/,
          /github.user_metadata.v1.Recalculation\Z/,
        ]

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.metric_prefix = "user_metadata_processor.discussion_answer"
          self.dead_letter_topic = "user_metadata.v0.DiscussionAnswer.DeadLetter"
        end

        # Public: User metadata that this stream processor should update for a given user.
        #
        # event - the UserMetadataEvent currently being processed
        # user  - a User with metadata affected by the event being processed
        #
        # Returns a Hash of metadata key/value pairs to update for the specified user.
        def metadata_updates(event, user)
          with_read do
            {
              discussion_answered_count: discussion_answered_count(user),
              discussion_answered_public_and_private_count: discussion_answered_public_and_private_count(user),
            }
          end
        end

        private

        # Private: Return the count of public discussions answered by the given author
        #
        # Returns Integer count
        def discussion_answered_count(user)
          with_read do
            repository_ids_with_authored_discussion_comments = DiscussionComment.
              chosen_answers.
              for_user(user.id).
              distinct.
              pluck(:repository_id)
            public_repo_ids = ::Repository.
              where(id: repository_ids_with_authored_discussion_comments).
              public_scope.
              pluck(:id)

            DiscussionComment.
              chosen_answers.
              for_user(user.id).for_repository(public_repo_ids).
              count
          end
        end

        def discussion_answered_public_and_private_count(user)
          repository_ids_with_authored_discussion_comments = DiscussionComment.
            chosen_answers.
            for_user(user.id).
            distinct.
            pluck(:repository_id)
          DiscussionComment.
            chosen_answers.
            for_user(user.id).for_repository(repository_ids_with_authored_discussion_comments).
            count
        end
      end
    end
  end
end
