# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PullRequestCommitCommentThread < Platform::Loader
      def self.load(viewer, pull_request_id, repository_id, commit_oid, path, position)
        thread_key = [pull_request_id, repository_id, commit_oid, path, position]
        self.for(viewer).load(thread_key)
      end

      def initialize(viewer)
        @viewer = viewer
      end

      def fetch(thread_keys)
        result = Hash.new { |hash, key| hash[key] = [] }

        Promise.all(thread_keys.map do |thread_key|
          pull_request_id, repository_id, commit_oid, path, position = *thread_key

          Platform::Loaders::ActiveRecord.load(::PullRequest, pull_request_id).then do |pull_request|
            next if T.must(pull_request).head_repository_id != repository_id && T.must(pull_request).base_repository_id != repository_id

            async_fetch_visible_thread(pull_request_id, repository_id, commit_oid, path, position).then do |thread|
              result[thread_key] = thread if thread
            end
          end
        end).sync

        result
      end

      private

      attr_reader :viewer

      def async_fetch_visible_thread(pull_request_id, repository_id, commit_oid, path, position)
        RepositoryVisibleCheck.load(viewer, repository_id, resource: "contents").then do |visible|
          next true if visible
          next false unless viewer&.site_admin?

          UnlockedRepositoryCheck.load(viewer, repository_id)
        end.then do |visible|
          next false unless visible

          Platform::Loaders::CommitCommentThread.load(repository_id, commit_oid, path, position).then do |thread|
            if GitHub.spamminess_check_enabled? && !viewer&.site_admin?
              thread = if viewer
                thread.reject do |comment|
                  comment.user_hidden? && comment.user_id != viewer.id
                end
              else
                thread.reject(&:user_hidden?)
              end
            end

            next if thread.empty?

            thread = thread.sort_by(&:id)

            PullRequestLockedAt.load(pull_request_id).then do |locked_at|
              next thread if locked_at.nil? || thread.last.created_at < locked_at

              thread.first.async_repository.then do |repository|
                Promise.all(thread.map do |comment|
                  comment.async_user.then { |user| repository.async_permit?(user, :write) }
                end).then do |comment_is_visible|
                  thread.select.each_with_index do |comment, index|
                    comment.created_at < locked_at || comment_is_visible[index]
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
