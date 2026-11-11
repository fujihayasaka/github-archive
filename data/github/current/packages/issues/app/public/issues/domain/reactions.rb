# typed: strict
# frozen_string_literal: true

module Issues
  class Domain
    class Reactions < GH::Domain::Base
      # Removes eyes emoji reactions for the given user IDs on an issue or comment.
      # Handles deletion, subscriber notification, and metrics.
      #
      # @param subject [Issue, IssueComment] The issue or comment to remove reactions from
      # @param user_ids [Array<Integer>] The user IDs whose eyes reactions should be removed
      #
      # @return [GH::Result] Ok with the number of reactions deleted, Error on failure
      # rubocop:disable Metrics/MethodLength
      sig { params(subject: T.any(Issue, IssueComment), user_ids: T::Array[Integer]).returns(GH::Result[Integer]) }
      def remove_eyes(subject:, user_ids:)
        return GH::Result::Ok.new(0) if user_ids.empty?

        reactions = case subject
        when Issue
          IssueReaction.where(issue_id: subject.id, user_id: user_ids, content: "eyes")
        when IssueComment
          IssueCommentReaction.where(issue_comment_id: subject.id, user_id: user_ids, content: "eyes")
        else
          T.absurd(subject)
        end

        deleted = reactions.delete_all
        record_eyes_removal(subject, deleted) if deleted.positive?

        GH::Result::Ok.new(deleted)
      rescue StandardError => e
        GH::Result::Error.new(e.message, e)
      end
      # rubocop:enable Metrics/MethodLength

      # Adds an eyes emoji reaction (👀) from the provided actor to the given issue or comment.
      # rubocop:disable Metrics/MethodLength
      sig { params(subject: T.any(Issue, IssueComment), actor: User).void }
      def add_eyes(subject, actor)
        eyes_emotion = Emotion.find_by_label("eyes")
        return unless eyes_emotion

        current_time = Time.current
        attrs = {
          "content" => eyes_emotion.content,
          "user_id" => actor.id,
          "repository_id" => subject.repository_id,
          "user_hidden" => false,
          "created_at" => current_time,
          "updated_at" => current_time
        }

        case subject
        when Issue
          reaction_attributes = attrs.merge("issue_id" => subject.id)

          ActiveRecord::Base.connected_to(role: :writing) do
            IssueReaction.insert_all([reaction_attributes])
          end

          IssueReaction.notify_subject_subscribers(subject)

        when IssueComment
          reaction_attributes = attrs.merge("issue_comment_id" => subject.id)

          ActiveRecord::Base.connected_to(role: :writing) do
            IssueCommentReaction.insert_all([reaction_attributes])
          end

          IssueCommentReaction.notify_subject_subscribers(subject)
        end

        GitHub.dogstats.increment("reaction", tags: ["action:create", "type:#{eyes_emotion.content}"])
      end
      # rubocop:enable Metrics/MethodLength

      private

      sig { params(subject: T.any(Issue, IssueComment), count: Integer).void }
      def record_eyes_removal(subject, count)
        case subject
        when Issue
          IssueReaction.notify_subject_subscribers(subject)
        when IssueComment
          IssueCommentReaction.notify_subject_subscribers(subject)
        end
        GitHub.dogstats.increment("reaction", tags: ["action:destroy", "type:eyes"], by: count)
      end
    end
  end
end
