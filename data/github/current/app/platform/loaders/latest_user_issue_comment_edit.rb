# typed: true
#frozen_string_literal: true

module Platform
  module Loaders
    class LatestUserIssueCommentEdit < Platform::Loader

      def self.load(model_id, repository_id)
        self.for.load([model_id, repository_id])
      end

      def fetch(model_and_repo_ids)
        model_ids = model_and_repo_ids.map(&:first)
        repository_ids = model_and_repo_ids.map(&:last).uniq

        bind_vars = {
          model_ids: model_ids,
          repository_ids: repository_ids
        }

        results = IssueCommentEdit.find_by_sql(build_sql_query(bind_vars))

        results.inject({}) do |fulfillments, issue_comment_edit|
          fulfillments[[issue_comment_edit.user_content_id, issue_comment_edit.repository_id]] = issue_comment_edit
          fulfillments
        end
      end

      private

      def build_sql_query(bind_vars)
        sql_query = Arel.sql(<<~SQL, **bind_vars)
          SELECT `issue_comment_edits`.*
          FROM `issue_comment_edits`
          INNER JOIN (
            SELECT `issue_comment_id`, MAX(id) AS max_id
            FROM `issue_comment_edits`
            WHERE `issue_comment_id` IN (:model_ids)
            GROUP BY `issue_comment_id`
          ) AS maxt ON `issue_comment_edits`.id = maxt.max_id AND `issue_comment_edits`.repository_id IN (:repository_ids)
        SQL
      end

      attr_reader :user_content_type
    end
  end
end
