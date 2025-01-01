# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::EditPullRequestReviewAPIService
      class EditPullRequestReviewAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::Attribution
        include Imports::Helpers::ContentCreation
        include Imports::Helpers::LiveMigrations
        include Imports::Helpers::ModelDelay
        include Helpers::ErrorHandler

        allow_access_for :client, allowed_clients: %w[octoshift elm migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::EditPullRequestReviewAPIService

        # Public: Implementation of the EditPullRequestReview Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::EditPullRequestReviewRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::EditPullRequestReviewResponse, or a Twirp::Error.
        def edit_pull_request_review(req, env)
          check_model_replication_delay!(ImportablePullRequestReview)

          # Validate args
          err = validate(req.id, req.updated_at, req.user_login, req.body&.value)
          return err if err

          # Fetch the user who edited the pull request review
          user = user_or_ghost(req.user_login)
          return Twirp::Error.not_found("User '#{req.user_login}' was not found.") unless user

          pull_request_review = replica(ImportablePullRequestReview).find_by(id: req.id)
          unless pull_request_review
            return Twirp::Error.not_found("PullRequestReview '#{req.id}' was not found.")
          end

          unless Repository.active.where(id: pull_request_review.repository_id).exists?
            return Twirp::Error.not_found("Repository not found.", octoshift_error_code: "REPOSITORY_DELETED")
          end

          # Only update if the incoming updated_at is newer than the latest timestamp on the pull request review
          err = check_outdated_updated_at(pull_request_review, req.updated_at)
          return err if err

          # Body presence requirements based on the review event:
          #   - Comment:         non-empty body is required
          #   - Approve:         empty body is allowed
          #   - Request changes: non-empty body is required
          if (pull_request_review.commented? || pull_request_review.changes_requested?) && req.body&.value.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "body")
          end

          rate_limited_mode(pull_request_review) do
            return edit(pull_request_review, user, req.body&.value, req.updated_at)
          end
        rescue Errors::UnableToEditError => error
          error.message
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def validate(id, updated_at, user_login, body)
          if id.negative? || id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "id")
          end
          if updated_at.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "updated_at")
          end
          if user_login.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_login") # rubocop:disable Style/RedundantReturn
          end
        end

        def edit(pull_request_review, user, body, updated_at)
          pull_request_review.update_body(body, user)
          pull_request_review.update(updated_at: updated_at.to_time)

          build_pull_request_review_hash(pull_request_review)
        end

        def build_pull_request_review_hash(pull_request_review)
          {
            id: pull_request_review.id
          }
        end
      end
    end
  end
end
