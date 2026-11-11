# typed: true
# frozen_string_literal: true

require "monolith-twirp-pullsd-jobs"

module Api::Internal::Twirp::Pullsd
  module Jobs
    module V1
      # Handler for the MonolithTwirp::Pullsd::Jobs::V1::JobsAPIService
      class JobsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["pullsd"]
        handles_service MonolithTwirp::Pullsd::Jobs::V1::JobsAPIService

        # Public: Implementation of the EnqueueMergeableUpdate Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Pullsd::Jobs::V1::EnqueueMergeableUpdateRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Pullsd::Jobs::V1::EnqueueMergeableUpdateResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Pullsd::Jobs::V1::EnqueueMergeableUpdateRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Pullsd::Jobs::V1::EnqueueMergeableUpdateResponse, Twirp::Error))
        end
        def enqueue_mergeable_update(req, env)
          pull_request_id = req.pull_request_id

          if pull_request_id.blank?
            return Twirp::Error.not_found("no pull request ID transmitted")
          end

          pull_request = PullRequest.find_by(id: pull_request_id)

          unless pull_request
            return Twirp::Error.not_found("no pull request found for the given ID")
          end

          priority = req.priority

          translated_priority = case priority
          when 1, :MERGE_PRIORITY_LOW
            :low
          when 2, :MERGE_PRIORITY_MEDIUM
            :medium
          when 3, :MERGE_PRIORITY_HIGH
            :high
          else
            # this should never be hit but we need to satisfy our case statement
            Twirp::Error.invalid_argument("invalid priority for enqueuing mergeable update: #{priority}")
          end

          begin
            pull_request.enqueue_mergeable_update(priority: translated_priority)

            MonolithTwirp::Pullsd::Jobs::V1::EnqueueMergeableUpdateResponse.new
          rescue => e
            Twirp::Error.internal(
              "failed to enqueue mergeable update for pull request: #{pull_request_id}. Error: #{e}"
            )
          end
        end
      end
    end
  end
end
