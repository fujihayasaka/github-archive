# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestCommitCommentThread < Platform::Objects::Base
      description "Represents a commit comment thread part of a pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, commit_comment_thread)
        commit_comment_thread.async_comments(permission.viewer).then do |comments|
          next false unless comments.any?

          permission.typed_can_access?("CommitComment", comments.first)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_pull_request(object).then do |result|
          next false unless result

          object.async_hide_from_user?(permission.viewer).then do |result|
            !result
          end
        end
      end

      scopeless_tokens_as_minimum

      implements Interfaces::RepositoryNode

      implements_node templates: [[:rprcct, :repo_id, :pull_request_commit_comment_thread_id]], as: "PRCCT", ready_date: Platform::Helpers::GlobalId::COHORT_3 do |pull_request_commit_comment_thread|
        promise =
        if pull_request_commit_comment_thread.is_a?(::Timeline::Placeholder::PullRequestCommitCommentThread)
          ::Platform::Models::PullRequestCommitCommentThread.load_from_global_id(pull_request_commit_comment_thread.id)
        else
          Promise.resolve(pull_request_commit_comment_thread)
        end
        promise.then do |prcct|
          prcct.async_pull_request.then do |pull_request|
            {
              prefix: :rprcct,
              repo_id: pull_request.repository_id,
              pull_request_commit_comment_thread_id: pull_request_commit_comment_thread.id
            }
          end
        end
      end

      field :path, String, "The file the comments were made on.", null: true
      field :position, Integer, "The position in the diff for the commit that the comment was made on.", null: true
      field :commit, Objects::Commit, method: :async_commit, description: "The commit the comments were made on.", null: false

      field :pull_request, Objects::PullRequest, method: :async_pull_request, description: "The pull request this commit comment thread belongs to", null: false

      field :comments, Connections.define(Objects::CommitComment), description: "The comments that exist in this thread.", null: false, connection: true do
        argument :skip, Integer, description: "Skips the first _n_ elements in the list.", visibility: :internal, required: false
      end

      def comments(**arguments)
        @object.async_comments(@context[:viewer]).then do |comments|
          StableArrayWrapper.new(comments)
        end
      end

      def self.load_from_global_id(id)
        Models::PullRequestCommitCommentThread.load_from_global_id(id)
      end

      def self.load_from_next_global_id(parsed_id)
        prefix = parsed_id.parts[:prefix]
        unless prefix == :rprcct
          raise(Platform::Errors::NotFound, "Template prefix '#{prefix}' does not match an existing global id template")
        end
        id = parsed_id.parts[:pull_request_commit_comment_thread_id]
        Models::PullRequestCommitCommentThread.load_from_global_id(id)
      end
    end
  end
end
