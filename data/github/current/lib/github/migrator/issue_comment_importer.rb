# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class IssueCommentImporter < GitHub::Migrator::Importer

      def import(attributes, options = {})
        return if attributes["body"].empty?
        comment = IssueComment.new do |issue_comment|
          issue = \
            model_from_source_url!(attributes["issue"]) ||
            model_from_source_url!(attributes["pull_request"]).try(:issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          issue_comment.issue = issue
          issue_comment.repository = issue.repository
          issue_comment.user = user_or_fallback(attributes["user"])
          issue_comment.body = attributes["body"]
          issue_comment.formatter = attributes["formatter"]
          issue_comment.created_at = attributes["created_at"]
        end

        import_model(comment)
      end
    end
  end
end
