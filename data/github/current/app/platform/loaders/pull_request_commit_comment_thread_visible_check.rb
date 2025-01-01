# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PullRequestCommitCommentThreadVisibleCheck < Platform::Loader
      def self.load(pull_request_id, repository_id, commit_oid, path, position, created_at, viewer)
        self.for(viewer).load([pull_request_id, repository_id, commit_oid, path, position, created_at])
      end

      def initialize(viewer)
        @viewer = viewer
      end

      attr_reader :viewer

      def fetch(thread_identifiers)
        result = Hash.new(false)

        Promise.all(thread_identifiers.map do |identifier|
          pull_request_id, repository_id, commit_oid, path, position, created_at = *identifier

          RepositoryVisibleCheck.load(viewer, repository_id, resource: "contents").then do |visible|
            next true if visible
            next false unless viewer&.site_admin?

            UnlockedRepositoryCheck.load(viewer, repository_id)
          end.then do |visible|
            next false unless visible

            PullRequestLockedAt.load(pull_request_id).then do |locked_at|
              next true if locked_at.nil? || locked_at > created_at

              CommitCommentAnyCollaboratorAuthor.load(repository_id, commit_oid, path, position)
            end
          end.then do |visible|
            result[identifier] = visible
          end
        end).sync

        result
      end
    end
  end
end
