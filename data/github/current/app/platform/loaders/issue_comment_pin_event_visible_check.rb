# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class IssueCommentPinEventVisibleCheck < Platform::Loader
      def self.load(viewer, subject_id, subject_type)
        self.for(viewer).load([subject_id, subject_type])
      end

      def initialize(viewer)
        @viewer = viewer
      end

      def fetch(subject_ids_and_types)
        result = Hash.new(false)

        issue_comment_ids = subject_ids_and_types.each_with_object([]) do |(subject_id, subject_type), ids|
          if issue_comment_subject?(subject_id, subject_type)
            ids << subject_id
          else
            result[[subject_id, subject_type]] = false
          end
        end

        issue_comment_ids.uniq!

        return result if issue_comment_ids.empty?

        issue_comments = IssueComment.where(id: issue_comment_ids).to_a
        issue_comments_by_id = issue_comments.index_by(&:id)

        hidden_from_user_promises = issue_comments.map do |issue_comment|
          issue_comment.async_hide_from_user?(@viewer)
        end

        Promise.all(hidden_from_user_promises).then do |hidden_results|
          hidden_lookup = {}

          issue_comments.each_with_index do |issue_comment, index|
            hidden_lookup[issue_comment.id] = hidden_results[index]
          end

          subject_ids_and_types.each do |subject_id, subject_type|
            next unless issue_comment_subject?(subject_id, subject_type)

            issue_comment = issue_comments_by_id[subject_id]

            result[[subject_id, subject_type]] =
              if issue_comment.nil?
                false
              else
                !hidden_lookup.fetch(issue_comment.id, false)
              end
          end

          result
        end
      end

      private

      def issue_comment_subject?(subject_id, subject_type)
        subject_type == IssueComment.name && subject_id.present?
      end
    end
  end
end
