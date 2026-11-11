# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PinnedIssueComment < Platform::Objects::Base
      docs_category :issues
      description "A comment pinned to an Issue."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_issue_comment.then do |issue_comment|
          permission.typed_can_access?("IssueComment", issue_comment)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_issue_comment.then do |issue_comment|
          next false if T.must(issue_comment).hide_from_user?(permission.viewer)
          T.must(issue_comment).readable_by?(permission.viewer)
        end
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
          [:pic, :repository_id, :issue_id, :pinned_issue_comment_id],
        ], as: "PIC", ready_date: "2026-01-08" do |pinned_issue_comment|
        {
          prefix: :pic,
          repository_id: pinned_issue_comment.repository_id,
          issue_id: pinned_issue_comment.issue_id,
          pinned_issue_comment_id: pinned_issue_comment.id
        }
      end

      database_id_field
      full_database_id_field

      field :issue_comment, Objects::IssueComment, method: :async_issue_comment, description: "The comment that was pinned.", null: false
      field :issue, Objects::Issue, method: :async_issue, description: "The issue that this comment belongs to.", null: false
      field :pinned_at, Scalars::DateTime, description: "Identifies when the comment was pinned.", null: false, method: :created_at
      field :pinned_by, Interfaces::Actor, description: "The actor that pinned this comment.", null: false
      def pinned_by
        Platform::Loaders::ActiveRecordAssociation.load(@object, :pinned_by).then do |_user|
          @object.safe_pinned_by
        end
      end
    end
  end
end
