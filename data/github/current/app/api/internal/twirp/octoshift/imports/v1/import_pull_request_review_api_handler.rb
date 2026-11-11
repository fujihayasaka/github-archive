# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handles the creation of imported pull request review data.
      class ImportPullRequestReviewAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::Attribution
        include Imports::Helpers::ContentCreation
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelAvailability

        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportPullRequestReviewAPIService
        allow_access_for :client, allowed_clients: %w[octoshift elm migrations_vnext]

        # Public: Implementation of the ImportPullRequestReview Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportPullRequestReviewRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportPullRequestReviewResponse, or a Twirp::Error.
        def import_pull_request_review(req, env)
          check_datastore_available_for_writes!(ImportablePullRequestReview)

          if req.pull_request_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "pull_request_id")
          end
          if req.state == :PULL_REQUEST_REVIEW_STATE_INVALID
            return Twirp::Error.invalid_argument("must be non-empty", argument: "state")
          end
          if req.head_sha.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "head_sha")
          end
          if req.created_at.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "created_at")
          end
          if req.submitted_at.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "submitted_at")
          end

          pull_request = replica(PullRequest).find_by(id: req.pull_request_id)

          unless pull_request
            return Twirp::Error.not_found("Pull Request not found.", argument: "pull_request_id", value: req.pull_request_id.to_s)
          end

          repo = Repository.active.find_by(id: pull_request.repository_id)
          return Twirp::Error.not_found("Repository not found.", octoshift_error_code: "REPOSITORY_DELETED") unless repo

          # Ghost is allowed for preserving the review data in case of a deleted account/service account, etc.
          review_user = user_or_ghost(req.user_login)
          unless review_user
            return Twirp::Error.not_found("Pull Request Review user not found.", argument: "user_login", value: req.user_login)
          end

          # Querying on `user_id` and `submitted_at` compound index for pull request reviews
          review_exists = replica(PullRequestReview).query do |klass|
            klass.where(
            pull_request_id: pull_request.id,
            created_at: req.created_at.to_time,
            user_id: review_user.id,
            submitted_at: req.submitted_at.to_time
            ).exists?
          end

          return already_exists_error_handler("PullRequestReview") if review_exists

          # Create a PullRequestReview in a pending state while threads and comments are added. The proper review
          # state is updated after theads are created to avoid any model validations associated with the state of
          # the review before threads/comments are added.
          review = ImportablePullRequestReview.new(
            pull_request: pull_request,
            user: review_user,
            state: :pending,
            head_sha: req.head_sha,
            created_at: req.created_at.to_time,
            submitted_at: req.submitted_at.to_time,
            body: req.body&.value,
            formatter: :markdown
          )

          twirp_error = nil

          begin
            if FeatureFlag.vexi.enabled?(:elm_pr_review_save, repo.owner, default: false)
              rate_limited_mode(review) do
                unless review.save
                  raise Errors::InvalidReviewError, save_model_error_handler(review)
                end
              end
            end

            thread_creator = Services::PullRequestReviewThreadCreator.new(pull_request: pull_request, review: review)

            req.threads.each do |thread_data|
              thread_creator.create_thread(thread_data)
            end

            req.comments.each do |comment_data|
              thread_creator.validate_reply!(comment_data)
              thread_creator.create_reply_comment(thread_id: comment_data.thread_id&.value, reply_to_id: comment_data.reply_to_id&.value, comment_data: comment_data)
            end

            # State is updated after threads and comments because the review's state must
            # be in a :pending state while comments/threads are added.
            review.state = Services::PullRequestReviewThreadCreator::REVIEW_STATE_MAP[req.state]
            rate_limited_mode(review) do
              unless review.save
                raise Errors::InvalidReviewError, save_model_error_handler(review)
              end
            end
          rescue Errors::InvalidReviewError => invalid_review_error
            twirp_error = rate_limit_error_handler(invalid_review_error.message)
          end

          return twirp_error unless twirp_error.nil?

          ActiveRecord::Base.connected_to(role: :writing) do
            review_request = pull_request.review_requests_for(review_user).first

            # Associate review with the user's review request.
            review_request.pull_request_reviews << review if review_request
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            pull_request_review = build_pull_request_review_hash(review)

            # NOTE: In the batched-import flow, this handler is called for the
            # initial batch only (with state :pending and the first slice of threads).
            # The review starts with zero threads, so this count check still
            # validates parity between the request's batch and what we persisted -
            # it is a per-call check, not a whole-review-completeness check. The
            # subsequent batches go through ImportPullRequestReviewThreadsAPIHandler.
            unless req.threads.count == pull_request_review[:review_threads].count
              error_message = "PullRequestReviewThread counts don't match"

              GitHub.logger.error(
                error_message,
                "gh.migration_tools.migration.pull_request_review.from_review_threads": req.threads.inspect,
                "gh.migration_tools.migration.pull_request_review.to_review_threads": pull_request_review[:review_threads].inspect,
                "code.function": __method__,
                "code.namespace": self.class
              )

              return Twirp::Error.canceled(error_message, octoshift_error_code: "PULL_REQUEST_REVIEW_THREADS_MISMATCH")
            end

            unless req.threads.map { |t| t.comments.count }.sum == pull_request_review[:review_threads].map { |t| t[:review_comments].count }.sum
              error_message = "PullRequestReviewComment counts don't match"

              GitHub.logger.error(
                error_message,
                "gh.migration_tools.migration.pull_request_review.from_review_threads": req.threads.inspect,
                "gh.migration_tools.migration.pull_request_review.to_review_threads": pull_request_review[:review_threads].inspect,
                "code.function": __method__,
                "code.namespace": self.class
              )

              return Twirp::Error.canceled(error_message, octoshift_error_code: "PULL_REQUEST_REVIEW_COMMENTS_MISMATCH")
            end

            { pull_request_review: pull_request_review }
          end
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        rescue Api::Internal::Twirp::Octoshift::Errors::DatastoreUnavailableForWrites => error
          datastore_unavailable_for_writes_error_handler(error.role)
        rescue ActiveRecord::RecordNotFound => error
          Twirp::Error.canceled("Could not create pull request review: #{error.model} not found")
        end

        private

        def build_pull_request_review_hash(pull_request_review)
          review_threads = pull_request_review.review_threads.map do |thread|
            review_comments = thread.review_comments.map do |comment|
              { id: comment.id }
            end

            { id: thread.id, review_comments: review_comments }
          end

          {
            id: pull_request_review.id,
            review_threads: review_threads
          }
        end
      end
    end
  end
end
