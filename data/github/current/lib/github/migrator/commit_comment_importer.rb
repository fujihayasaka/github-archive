# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class CommitCommentImporter < GitHub::Migrator::Importer

      def import(attributes, options = {})
        comment = CommitComment.new do |commit_comment|
          commit_comment.repository = model_from_source_url!(attributes["repository"])
          commit_comment.user = user_or_fallback(attributes["user"])
          commit_comment.body = attributes["body"]
          commit_comment.formatter = attributes["formatter"]
          commit_comment.path = attributes["path"]
          commit_comment.position = attributes["position"]
          commit_comment.commit_id = attributes["commit_id"]
          commit_comment.created_at = attributes["created_at"]
        end

        import_model(comment)
      end
    end
  end
end
