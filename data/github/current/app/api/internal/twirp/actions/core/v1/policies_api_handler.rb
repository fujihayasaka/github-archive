# typed: true
# frozen_string_literal: true

require "monolith-twirp-actions-core"

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # Handler for the MonolithTwirp::Actions::Core::V1::PoliciesAPIService
      class PoliciesAPIHandler < Api::Internal::Twirp::Handler

        allow_access_for :client, allowed_clients: ["launch"].freeze
        handles_service MonolithTwirp::Actions::Core::V1::PoliciesAPIService

        resolve_tenant_context do |req, _env|
          repo_id = Platform::Helpers::NodeIdentification.from_global_id(req.repository_id.global_id).last
          begin
            repo = Repositories::Public.get_active_or_deleted!(repo_id)
            next repo.owner&.business
          rescue ActiveRecord::RecordNotFound => err
            Twirp::Error.not_found(err.message)
          end
        end

        # Public: Implementation of the CheckActionsPolicy Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::CheckActionsPolicyRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::CheckActionsPolicyResponse, or a Twirp::Error.
        def check_actions_policy(req, env)
          CheckActionsPolicy.call(req)
        end

        # Public: Implementation of the CheckWorkflowsPolicy Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::CheckWorkflowsPolicyRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::CheckWorkflowsPolicyResponse, or a Twirp::Error.
        def check_workflows_policy(req, env)
          CheckWorkflowsPolicy.call(req)
        end
      end
    end
  end
end
