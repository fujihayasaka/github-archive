# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class IssuePostProcessor < BasePostProcessor
      def joins
        [:comments, :labels, { repository: :labels }]
      end

      # Public: Post processing an issue does the following:
      #
      #   1. Applies labels.
      #   2. Rewrites urls referencing other issues in comment bodies.
      #   3. Rewrites @mentions in comment bodies.
      #   4. Rewrites urls referencing other issues in issue body.
      #   5. Rewrites @mentions in the issue body.
      def process(issue, attributes, actor, batch_load_associations: false)
        # Apply labels.
        attributes["labels"].each do |label_source_url|
          label_name = CGI.unescape(label_source_url.split("/")[6..-1].join("/"))
          if label = issue.repository.labels.detect { |l| l.name == label_name }
            next if issue.labels.include?(label)
            issue.labels << label
          end
        end

        if batch_load_associations
          comment_ids = issue.comments.pluck(:id)

          comment_ids.each_slice(BATCH_SIZE) do |comment_batch_ids|
            # Batch update update_at attribute
            IssueComment.where(id: comment_batch_ids).update_all("issue_comments.updated_at = issue_comments.created_at")

            # Rewrite body content
            IssueComment.where(id: comment_batch_ids).find_each do |issue_comment|
              rewrite_comment(issue_comment)
            end
          end

          issue.update_column(:issue_comments_count, comment_ids.length)
        else
          issue.comments.update_all("issue_comments.updated_at = issue_comments.created_at")
          issue.comments.each do |issue_comment|
            rewrite_comment(issue_comment)
          end
          issue.update_column(:issue_comments_count, issue.comments.length)
        end

        issue.body = user_content_rewriter.process(issue)
        update_body_with_references(issue)

        # Update milestone counts.
        issue.update_milestone_counts!
      end
    end
  end
end
