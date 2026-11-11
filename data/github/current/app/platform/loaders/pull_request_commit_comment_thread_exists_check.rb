# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PullRequestCommitCommentThreadExistsCheck < Platform::Loader
      def self.load(viewer, pull_request_id, repository_id, commit_oid, path, position)
        thread_key = build_thread_key(
          pull_request_id, repository_id, commit_oid, path, position
        )
        self.for(viewer).load(thread_key)
      end

      def initialize(viewer)
        @viewer = viewer
      end

      def self.build_thread_key(pull_request_id, repository_id, commit_oid, path, position)
        path = nil if path.blank?

        [pull_request_id, repository_id, commit_oid, path, position]
      end

      attr_reader :viewer

      def fetch(thread_keys)
        commit_comment_thread_keys = []
        commit_oids_by_pull_request_id = Hash.new { |hash, key| hash[key] = [] }

        thread_keys.each do |pull_request_id, repository_id, commit_oid, path, position|
          commit_oids_by_pull_request_id[pull_request_id] << commit_oid
          commit_comment_thread_keys << [repository_id, commit_oid, path, position]
        end

        scope = ::CommitComment.
          filter_spam_for(viewer).
          with_pull_requests(commit_oids_by_pull_request_id).
          in_threads(commit_comment_thread_keys)

        result = scope.
          pluck(
            Arel.sql("`pull_requests`.`id`"),
            Arel.sql("`commit_comments`.`repository_id`"),
            Arel.sql("`commit_comments`.`commit_id`"),
            Arel.sql("`commit_comments`.`path`"),
            Arel.sql("`commit_comments`.`position`"),
            Arel.sql("`commit_comments`.`created_at`")).
          group_by { |pull_request_id, repository_id, commit_id, path, position, _created_at| [pull_request_id, repository_id, commit_id, path, position] }.
          transform_values { |values| values.map { |_pull_request_id, _repository_id, _commit_id, _path, _position, created_at| created_at }.min }.
          map { |(pull_request_id, repository_id, commit_id, path, position), created_at| [pull_request_id, repository_id, commit_id, path, position, created_at] }

        thread_existance = Hash.new { false }

        Promise.all(result.map do |pull_request_id, repository_id, commit_oid, path, position, created_at|
          PullRequestCommitCommentThreadVisibleCheck.load(pull_request_id, repository_id, commit_oid, path.dup, position, created_at, viewer).then do |visible|
            next unless visible

            path&.force_encoding("utf-8")

            key = self.class.build_thread_key(
              pull_request_id, repository_id, commit_oid, path, position
            )

            thread_existance[key] = true
          end
        end).sync

        thread_existance
      end
    end
  end
end
