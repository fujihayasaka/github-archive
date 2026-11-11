# typed: strict
# frozen_string_literal: true

module Issues
  class Domain
    class Comments < GH::Domain::Base

      # Creates a pinned issue comment.
      sig do
        params(
          issue_comment: IssueComment,
          actor: User,
        ).returns(GH::Result[Issues::IPinnedIssueComment])
      end
      def pin(issue_comment:, actor:) # rubocop:disable Metrics/MethodLength
        # If the comment is already pinned, return it.
        existing_pinned = issue_comment.issue&.pinned_issue_comment
        return GH::Result::Ok.new(existing_pinned) if existing_pinned&.issue_comment_id == issue_comment.id

        PinnedIssueComment.transaction do
          existing_pinned&.destroy!
          pinned_comment = PinnedIssueComment.create!(issue_comment:, pinned_by: actor)

          GH::Result::Ok.new(pinned_comment)
        end
      rescue ActiveRecord::RecordInvalid => e
        GH::Result::Error::Validation.new(e.record, message: e.message)
      rescue ActiveRecord::ActiveRecordError => e
        GH::Result::Error.new("Failed to pin issue comment: #{e.message}")
      end

      # Unpins an issue comment.
      sig do
        params(
          issue_comment: IssueComment,
          actor: User
        ).returns(GH::Result[T::Boolean])
      end
      def unpin(issue_comment:, actor:)
        issue_comment.pinned_issue_comment&.destroy!
        issue_comment.reload

        GH::Result::Ok.new(true)
      rescue ActiveRecord::RecordNotFound => e
        GH::Result::Error::NotFound.new("Failed to unpin Issue Comment: #{e.message}")
      rescue ActiveRecord::ActiveRecordError => e
        GH::Result::Error.new("Failed to unpin Issue Comment: #{e.message}")
      end
    end
  end
end
