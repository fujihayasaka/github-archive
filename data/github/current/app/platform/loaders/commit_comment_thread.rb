# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class CommitCommentThread < Platform::Loader
      def self.load(repository_id, commit_id, path, position)
        thread_key = [repository_id, commit_id, path, position]
        self.for.load(thread_key)
      end

      def fetch(thread_keys)
        fetch_threads(thread_keys)
      end

      private

      def fetch_threads(thread_keys)
        comments = ::CommitComment.in_threads(thread_keys).order(:id)

        comments.group_by do |comment|
          [
            comment.repository_id,
            comment.commit_id,
            comment.path,
            comment.position,
          ]
        end.tap do |results|
          results.default_proc = -> (_, _) { [] }
        end
      end
    end
  end
end
