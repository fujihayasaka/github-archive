# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handles the creation of an imported commit comment.
      class ImportCommitCommentAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::Attribution
        include Imports::Helpers::ContentCreation
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay
        include Imports::Helpers::AlreadyExists

        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportCommitCommentAPIService
        allow_access_for :client, allowed_clients: %w[octoshift migrations_vnext]

        # Public: Implementation of the ImportCommitComment Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportCommitCommentRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportCommitCommentRequest, or a Twirp::Error.
        def import_commit_comment(req, env)
          check_model_replication_delay!(ImportableCommitComment)

          repository = replica(Repository).find_by(id: req.repository_id)
          return Twirp::Error.not_found("Repository not found", argument: "repository_id", value: req.repository_id.to_s, octoshift_error_code: "REPOSITORY_DELETED") unless repository && repository.active?

          if req.body.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "body")
          end

          if req.commit_id.empty?
            return Twirp::Error.invalid_argument("must be a positive integer", argument: "commit_id")
          end

          if req.created_at.nil?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "created_at")
          end

          user = user_or_ghost(req.author_login)
          return Twirp::Error.not_found("User '#{req.author_login}' was not found.") unless user

          begin
            commit = Repositories.domain.commits.by_oid(repository: repository, commit_oid: req.commit_id)
          rescue GitRPC::ObjectMissing
            return Twirp::Error.malformed("Commit '#{req.commit_id}' was not found.", octoshift_error_code: "COMMIT_MISSING") unless commit
          end

          check_for_existing_record!(CommitComment,
              repository_id: req.repository_id,
              user_id: user.id,
              commit_id: req.commit_id,
              created_at: req.created_at.to_time
          )

          new_commit_comment = ImportableCommitComment.new(
            repository_id: req.repository_id,
            commit_id: req.commit_id,
            user_id: user.id,
            body: req.body,
            created_at: req.created_at.to_time,
            path: (req.path.value if req.path),
            position: (req.position.value if req.position)
          )

          rate_limited_mode(new_commit_comment) do
            return save_model_error_handler(new_commit_comment) unless new_commit_comment.save
          end

          { id: new_commit_comment.id }
        rescue Api::Internal::Twirp::Octoshift::Errors::AlreadyExists => error
          error.to_twirp_error
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def commit_comment_exists?(repository, user, req)
          replica(CommitComment).query do |klass|
            klass.where(
              repository: repository,
              user: user,
              commit_id: req.commit_id,
              created_at: req.created_at.to_time
            ).exists?
          end
        end
      end
    end
  end
end
