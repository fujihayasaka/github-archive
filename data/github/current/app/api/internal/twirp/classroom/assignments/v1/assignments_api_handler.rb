# typed: true
# frozen_string_literal: true

require "monolith-twirp-classroom-assignments"

module Api::Internal::Twirp::Classroom
  module Assignments
    module V1
      # Handler for the MonolithTwirp::Classroom::Assignments::V1::AssignmentsAPIService
      class AssignmentsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["classroom"]
        handles_service MonolithTwirp::Classroom::Assignments::V1::AssignmentsAPIService

        # Public: Implementation of the ExecuteAutogradingWorkflows Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::Assignments::V1::ExecuteAutogradingWorkflowsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::Assignments::V1::ExecuteAutogradingWorkflowsResponse, or a Twirp::Error.
        def execute_autograding_workflows(req, env)
          repo_ids = req.repo_ids
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repo_ids") if repo_ids.empty?

          actor_id = id_argument(req.actor_id)
          unless actor_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "actor_id")
          end

          Repository.where(id: repo_ids.to_a).map do |repo|
            repo.dispatch_event(
              actor_id,
              "repository_dispatch"
            )
          end

          {}
        end
      end
    end
  end
end
