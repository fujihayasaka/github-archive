# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::EditPullRequestReviewCommentAPIService
      class EditPullRequestReviewCommentAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::Attribution
        include Imports::Helpers::ContentCreation
        include Imports::Helpers::LiveMigrations
        include Imports::Helpers::ModelDelay
        include Helpers::ErrorHandler

        allow_access_for :client, allowed_clients: %w[octoshift migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::EditPullRequestReviewCommentAPIService

        # Public: Implementation of the EditPullRequestReviewComment Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::EditPullRequestReviewCommentRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::EditPullRequestReviewCommentResponse, or a Twirp::Error.
        def edit_pull_request_review_comment(req, env)
          check_model_replication_delay!(ImportablePullRequestReviewComment)

          # Validate args
          err = validate(req.id, req.action, req.body&.value, req.updated_at, req.user_login)
          return err if err

          # Fetch the user who edited the pull request review comment
          user = user_or_ghost(req.user_login)
          return Twirp::Error.not_found("User '#{req.user_login}' was not found.") unless user

          pull_request_review_comment = replica(ImportablePullRequestReviewComment).find_by(id: req.id)
          unless pull_request_review_comment
            return Twirp::Error.not_found("PullRequestReviewComment '#{req.id}' was not found.")
          end

          # Only update if the incoming updated_at is newer than the latest timestamp on the
          # pull request review comment
          err = check_outdated_updated_at(pull_request_review_comment, req.updated_at)
          return err if err

          rate_limited_mode(pull_request_review_comment) do
            if req.action == :LIVE_MIGRATION_ACTION_EDITED
              return edit(pull_request_review_comment, user, req.body&.value, req.updated_at)
            elsif req.action == :LIVE_MIGRATION_ACTION_DELETED
              return delete(pull_request_review_comment)
            end
          end
        rescue Errors::UnableToEditError => error
          error.message
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def edit(pull_request_review_comment, user, body, updated_at)
          pull_request_review_comment.update_body(body, user)
          pull_request_review_comment.update(updated_at: updated_at.to_time)

          build_pull_request_review_comment_hash(pull_request_review_comment)
        end

        # For now we don't support deleting pull request review comments. Update this
        # method once we change this and allow deletions.
        def delete(pull_request_review_comment)
          Twirp::Error.canceled("Pull request review comment deletion is not supported at this time")
        end

        def validate(id, action, body, updated_at, user_login)
          if id.negative? || id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "id")
          end
          if action == :LIVE_MIGRATION_ACTION_INVALID
            return Twirp::Error.invalid_argument("must be a valid enum", argument: "action")
          end
          if action == :LIVE_MIGRATION_ACTION_EDITED && body.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "body")
          end
          if updated_at.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "updated_at")
          end
          if user_login.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_login") # rubocop:disable Style/RedundantReturn
          end
        end

        def build_pull_request_review_comment_hash(pull_request_review_comment)
          {
            id: pull_request_review_comment.id
          }
        end
      end
    end
  end
end
