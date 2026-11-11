# typed: true
# frozen_string_literal: true

require "monolith-twirp-actionsresults-core"

module Api::Internal::Twirp::ActionsResults
  module Core
    module V1
      class ArtifactsApiHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["actions_results"].freeze
        handles_service MonolithTwirp::ActionsResults::Core::V1::ArtifactsAPIService
        connected_to_writing_for :create_artifact, :delete_artifact_from_monolith

        resolve_tenant_context do |req, _env|
          case req
          when MonolithTwirp::ActionsResults::Core::V1::CreateArtifactRequest # special case, no repo id in request
            repository_id = ActiveRecord::Base.connected_to(role: :reading) do
              CheckSuite.find_by(id: req.check_suite_id)&.repository_id
            end

            Repositories::Public.resolve_tenant(id: repository_id)
          else
            next nil unless req.respond_to?(:repository_id)
            Repositories::Public.resolve_tenant(id: req.repository_id)
          end
        end

        # Public: Implementation of the CreateArtifact Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::ActionsResults::Core::V1::CreateArtifactRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::ActionsResults::Core::V1::CreateArtifactResponse, or a Twirp::Error.
        def create_artifact(req, env)
          CreateArtifact.call(req, env)
        end

        # Public: Implementation of the ListArtifacts Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::ActionsResults::Core::V1::ListArtifactsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::ActionsResults::Core::V1::ListArtifactsResponse, or a Twirp::Error.
        def list_artifacts(req, env)
          ListArtifacts.call(req, env)
        end

        # Public: Implementation of the DeleteArtifactFromMonolith Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::ActionsResults::Core::V1::DeleteArtifactFromMonolithRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::ActionsResults::Core::V1::DeleteArtifactFromMonolithResponse, or a Twirp::Error.
        def delete_artifact_from_monolith(req, env)
          DeleteArtifactFromMonolith.call(req, env)
        end
      end
    end
  end
end
