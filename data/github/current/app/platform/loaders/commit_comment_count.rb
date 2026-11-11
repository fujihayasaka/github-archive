# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class CommitCommentCount < Platform::Loader
      def self.load(repo_id, oid)
        self.for(repo_id).load(oid)
      end

      def initialize(repo_id)
        @repo_id = repo_id
      end

      def fetch(oids)
        counts = CommitComment.connection.select_rows(Arel.sql(<<-SQL, repo_id: @repo_id, oids: oids)).to_h
          SELECT commit_id, COUNT(commit_comments.id) FROM commit_comments
          WHERE repository_id = :repo_id
            AND user_hidden = false
            AND commit_id IN (:oids)
          GROUP BY commit_id
        SQL

        oids.map { |oid| [oid, counts[oid] || 0] }.to_h
      end
    end
  end
end
