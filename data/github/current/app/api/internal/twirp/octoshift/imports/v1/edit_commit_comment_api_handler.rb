# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::EditCommitCommentAPIService
      class EditCommitCommentAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::ModelDelay
        include Imports::Helpers::ContentCreation
        include Imports::Helpers::LiveMigrations
        include Helpers::ErrorHandler

        allow_access_for :client, allowed_clients: %w[elm migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::EditCommitCommentAPIService

        # Public: Implementation of the EditCommitComment Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::EditCommitCommentRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::EditCommitCommentResponse, or a Twirp::Error.
        def edit_commit_comment(req, env)
          check_model_replication_delay!(CommitComment)

          begin
            commit_comment = CommitComment.find(req.id)
          rescue ActiveRecord::RecordNotFound
            return Twirp::Error.not_found("CommitComment not found.", argument: "id", value: req.id.to_s, octoshift_error_code: "COMMIT_COMMENT_NOT_FOUND")
          end

          case req.action
          when :LIVE_MIGRATION_ACTION_EDITED
            err = check_outdated_updated_at(commit_comment, req.updated_at)
            return err if err

            commit_comment.body = req.body
            commit_comment.updated_at = req.updated_at.to_time if req.updated_at

            rate_limited_mode(commit_comment) do
              unless commit_comment.save
                return Twirp::Error.canceled("Could not update commit_comment: #{commit_comment.errors.full_messages.join(", ")}.")
              end
            end
            MonolithTwirp::Octoshift::Imports::V1::EditCommitCommentResponse.new
          when :LIVE_MIGRATION_ACTION_DELETED
            rate_limited_mode(commit_comment) do
              unless commit_comment.destroy
                return Twirp::Error.canceled("Could not destroy commit_comment: #{commit_comment.errors.full_messages.join(", ")}.")
              end
            end
            MonolithTwirp::Octoshift::Imports::V1::EditCommitCommentResponse.new
          else
            # This should never happen; if it does, the client is sending an invalid request.
            Twirp::Error.invalid_argument("Invalid LiveMigrationAction", argument: "action")
          end
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end
      end
    end
  end
end
