# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class RepositoryCommitCommentCount < Platform::Loader
      def self.load(repo_id)
        self.for.load(repo_id)
      end

      def fetch(repo_ids)
        count = CommitComment.connection.select_rows(Arel.sql(<<-SQL, repo_ids: repo_ids)).to_h
          SELECT repository_id, COUNT(repository_id) FROM commit_comments
          WHERE repository_id IN (:repo_ids)
            AND user_hidden = 0
          GROUP BY repository_id
        SQL

        repo_ids.map { |id| [id, count[id] || 0] }.to_h
      end
    end
  end
end
