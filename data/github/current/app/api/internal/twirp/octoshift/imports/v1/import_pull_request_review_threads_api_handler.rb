# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handles the batched creation of imported pull request review threads and comments
      # for an existing pull request review.
      class ImportPullRequestReviewThreadsAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::Attribution
        include Imports::Helpers::ContentCreation
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelAvailability

        REVIEW_STATE_MAP = Services::PullRequestReviewThreadCreator::REVIEW_STATE_MAP

        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportPullRequestReviewThreadsAPIService
        allow_access_for :client, allowed_clients: %w[octoshift elm migrations_vnext]

        # Public: Implementation of the ImportPullRequestReviewThreads Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportPullRequestReviewThreadsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportPullRequestReviewThreadsResponse, or a Twirp::Error.
        def import_pull_request_review_threads(req, env)
          check_datastore_available_for_writes!(ImportablePullRequestReview)

          if req.review_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "review_id")
          end

          review = replica(ImportablePullRequestReview).find_by(id: req.review_id)
          unless review
            return Twirp::Error.not_found("PullRequestReview not found.", argument: "review_id", value: req.review_id.to_s)
          end

          if req.threads.empty? && req.comments.empty?
            return Twirp::Error.invalid_argument("must provide at least one thread or comment", argument: "threads")
          end

          pull_request = replica(PullRequest).find_by(id: review.pull_request_id)
          unless pull_request
            return Twirp::Error.not_found("Pull Request not found.", argument: "pull_request_id")
          end

          repo = Repository.active.find_by(id: pull_request.repository_id)
          return Twirp::Error.not_found("Repository not found.", octoshift_error_code: "REPOSITORY_DELETED") unless repo

          errors = []
          twirp_error = nil
          created_threads = []
          created_reply_comments = []

          begin
            thread_creator = Services::PullRequestReviewThreadCreator.new(pull_request: pull_request, review: review)

            req.threads.each_with_index do |thread_data, index|
              begin
                # Track the created thread to return only this batch's threads.
                created_threads << thread_creator.create_thread(thread_data)
              rescue Errors::InvalidReviewError => e
                errors << { batch_index: index, error_message: "threads[#{index}]: #{e.twirp_error.msg}" }
              end
            end

            req.comments.each_with_index do |comment_data, index|
              begin
                thread_creator.validate_reply!(comment_data)
                created_reply_comments << thread_creator.create_reply_comment(thread_id: comment_data.thread_id&.value, reply_to_id: comment_data.reply_to_id&.value, comment_data: comment_data)
              rescue Errors::InvalidReviewError => e
                errors << { batch_index: index, error_message: "comments[#{index}]: #{e.twirp_error.msg}" }
              end
            end

            # If a final state is provided, transition the review to that state.
            if req.state != :PULL_REQUEST_REVIEW_STATE_INVALID
              review.state = REVIEW_STATE_MAP[req.state]
              if req.submitted_at.present?
                review.submitted_at = req.submitted_at.to_time
              end
              rate_limited_mode(review) do
                unless review.save
                  raise Errors::InvalidReviewError, save_model_error_handler(review)
                end
              end
            end
          rescue Errors::InvalidReviewError => invalid_review_error
            twirp_error = rate_limit_error_handler(invalid_review_error.message)
          end

          return twirp_error unless twirp_error.nil?

          # Only return threads created in this batch, not all threads on the review.
          review_threads = created_threads.compact.map do |thread|
            review_comments = thread.review_comments.map do |comment|
              { id: comment.id }
            end

            { id: thread.id, review_comments: review_comments }
          end

          # Reply comments created in this batch, returned at the top level so the
          # caller can map them by index back to the request's `comments` array.
          review_comments = created_reply_comments.compact.map do |comment|
            { id: comment.id }
          end

          {
            review_threads: review_threads,
            review_comments: review_comments,
            batch_validation_errors: errors
          }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        rescue Api::Internal::Twirp::Octoshift::Errors::DatastoreUnavailableForWrites => error
          datastore_unavailable_for_writes_error_handler(error.role)
        rescue ActiveRecord::RecordNotFound => error
          Twirp::Error.canceled("Could not add threads to pull request review: #{error.model} not found")
        end
      end
    end
  end
end
