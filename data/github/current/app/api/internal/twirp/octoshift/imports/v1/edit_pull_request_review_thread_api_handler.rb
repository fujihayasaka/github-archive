# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::EditPullRequestReviewThreadAPIService
      class EditPullRequestReviewThreadAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::Attribution
        include Imports::Helpers::ContentCreation
        include Imports::Helpers::LiveMigrations
        include Imports::Helpers::ModelDelay
        include Helpers::ErrorHandler

        allow_access_for :client, allowed_clients: %w[octoshift elm migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::EditPullRequestReviewThreadAPIService

        # Public: Implementation of the EditPullRequestReviewThread Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::EditPullRequestReviewThreadRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::EditPullRequestReviewThreadResponse, or a Twirp::Error.
        def edit_pull_request_review_thread(req, env)
          check_model_replication_delay!(PullRequestReviewThread)

          # Validate args
          err = validate(req.id, req.state, req.user_login, req.updated_at, req.resolved_at)
          return err if err

          # Fetch the user who edited the pull request review thread
          user = user_or_ghost(req.user_login)
          return Twirp::Error.not_found("User '#{req.user_login}' was not found.") unless user

          pull_request_review_thread = replica(PullRequestReviewThread).find_by(id: req.id)
          unless pull_request_review_thread
            return Twirp::Error.not_found("PullRequestReviewThread '#{req.id}' was not found.")
          end

          # Only update if the incoming updated_at is newer than the latest timestamp on the pull request review thread
          err = check_outdated_updated_at(pull_request_review_thread, req.updated_at)
          return err if err

          rate_limited_mode(pull_request_review_thread) do
            return edit(pull_request_review_thread, req.state, user, req.resolved_at, req.updated_at)
          end
        rescue Errors::UnableToEditError => error
          error.message
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def edit(pull_request_review_thread, state, user, resolved_at, updated_at)
          # Set resolver and updated_at timestamps
          case state
          when :EDIT_PULL_REQUEST_REVIEW_THREAD_STATE_RESOLVED
            pull_request_review_thread.resolve(resolver: user)
            pull_request_review_thread.update(resolved_at: resolved_at.to_time, updated_at: updated_at.to_time)
          when :EDIT_PULL_REQUEST_REVIEW_THREAD_STATE_UNRESOLVED
            pull_request_review_thread.unresolve(unresolver: user)
            pull_request_review_thread.update(updated_at: updated_at.to_time)
          end

          build_pull_request_review_thread_hash(pull_request_review_thread)
        end

        def validate(id, state, user_login, updated_at, resolved_at)
          if id.negative? || id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "id")
          end
          if state == :EDIT_PULL_REQUEST_REVIEW_THREAD_STATE_INVALID
            return Twirp::Error.invalid_argument("must be a valid enum", argument: "state")
          end
          if user_login.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_login")
          end
          if updated_at.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "updated_at")
          end
          if resolved_at.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "resolved_at") # rubocop:disable Style/RedundantReturn
          end
        end

        def build_pull_request_review_thread_hash(pull_request_review_thread)
          {
            id: pull_request_review_thread.id
          }
        end
      end
    end
  end
end
