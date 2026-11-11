# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CommitCommentThread < Platform::Objects::Base
      description "A thread of comments on a commit."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, commit_comment_thread)
        commit_comment = commit_comment_thread.comments.first
        permission.typed_can_access?("CommitComment", commit_comment)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [[:r, :repository_id, :commit_oid, :path, :position]],
      as: "CCT", ready_date: Platform::Helpers::GlobalId::COHORT_3, uses_database_id: false, allow_nil_for: [:path, :position] do |commit_comment_thread|
        commit_comment_thread.async_repository.then do |repo|
          {
            prefix: :r,
            repository_id: repo.id,
            commit_oid: commit_comment_thread.commit_id,
            path: commit_comment_thread.path,
            position: commit_comment_thread.position,
          }
        end
      end

      implements Interfaces::RepositoryNode

      field :path, String, "The file the comments were made on.", null: true
      field :position, Integer, "The position in the diff for the commit that the comment was made on.", null: true

      field :commit, Objects::Commit, "The commit the comments were made on.", null: true

      def commit
        Loaders::ActiveRecord.load(::Repository, @object.repository.id).then do |repository|
          Loaders::GitObject.load(repository, @object.commit_id, expected_type: :commit)
        end
      end

      field :comments, resolver: Resolvers::CommitComments, description: "The comments that exist in this thread.", connection: true

      def self.load_from_next_global_id(parsed_id)
        build_commit_comment_thread(
          parsed_id.parts[:repository_id],
          parsed_id.parts[:commit_oid],
          parsed_id.parts[:path],
          parsed_id.parts[:position],
        )
      end

      def self.load_from_global_id(id)
        repository_id, commit_oid, path, position = id.split(":")
        build_commit_comment_thread(repository_id, commit_oid, path, position)
      end

      def self.build_commit_comment_thread(repository_id, commit_oid, path, position)
        Platform::Loaders::CommitCommentThread.load(repository_id.to_i, commit_oid, path, position&.to_i).then do |commit_comments|
          first_commit_comment = commit_comments.first
          next if first_commit_comment.nil?
          first_commit_comment.async_repository.then do |repository|
            next if repository.nil?
            ::CommitCommentThread.new(
              repository: repository,
              commit_id: first_commit_comment.commit_id,
              path: first_commit_comment.path,
              position: first_commit_comment.position,
              comments: commit_comments
            )
          end
        end
      end
    end
  end
end
