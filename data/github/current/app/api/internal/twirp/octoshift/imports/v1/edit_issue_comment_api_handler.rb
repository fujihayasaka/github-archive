# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::EditIssueCommentAPIService
      class EditIssueCommentAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::Attribution
        include Imports::Helpers::ContentCreation
        include Imports::Helpers::LiveMigrations
        include Imports::Helpers::ModelDelay
        include Helpers::ErrorHandler

        allow_access_for :client, allowed_clients: %w[octoshift elm migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::EditIssueCommentAPIService

        # Public: Implementation of the EditIssueComment Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::EditIssueCommentRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::EditIssueCommentResponse, or a Twirp::Error.
        def edit_issue_comment(req, env)
          check_model_replication_delay!(ImportableIssueComment)

          # Validate args
          err = validate(req.id, req.action, req.body, req.updated_at, req.user_login)
          return err if err

          # Fetch the user who edited the issue comment
          user = user_or_ghost(req.user_login)
          return Twirp::Error.not_found("User '#{req.user_login}' was not found.") unless user

          issue_comment = replica(ImportableIssueComment).find_by(id: req.id)
          unless issue_comment
            return Twirp::Error.not_found("IssueComment '#{req.id}' was not found.")
          end

          # Only update if the incoming updated_at is newer than the latest timestamp on the issue comment
          err = check_outdated_updated_at(issue_comment, req.updated_at)
          return err if err

          rate_limited_mode(issue_comment) do
            if req.action == :LIVE_MIGRATION_ACTION_EDITED
              return edit(issue_comment, user, req.body, req.updated_at)
            elsif req.action == :LIVE_MIGRATION_ACTION_DELETED
              return delete(issue_comment)
            end
          end
        rescue Errors::UnableToEditError => error
          error.message
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def validate(id, action, body, updated_at, user_login)
          if id.negative? || id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "id")
          end
          if action == :LIVE_MIGRATION_ACTION_INVALID
            return Twirp::Error.invalid_argument("must be a valid enum", argument: "action")
          end
          if action == :LIVE_MIGRATION_ACTION_EDITED && body.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "body")
          end
          if updated_at.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "updated_at")
          end
          if user_login.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_login") # rubocop:disable Style/RedundantReturn
          end
        end

        def edit(issue_comment, user, body, updated_at)
          issue_comment.update_body(body, user)
          issue_comment.update(updated_at: updated_at.to_time)

          build_issue_comment_hash(issue_comment)
        end

        def delete(issue_comment)
          return build_issue_comment_hash(issue_comment) if issue_comment.destroy # domain-isolation-query-violation:ignore:packages/issues (SELECT)

          # If we could not destroy the model, return an error
          Twirp::Error.canceled("Issue comment could not be deleted")
        end

        def build_issue_comment_hash(issue_comment)
          {
            id: issue_comment.id
          }
        end
      end
    end
  end
end
