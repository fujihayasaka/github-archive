# typed: true
# frozen_string_literal: true

require "monolith-twirp-classroom-access_check"

module Api::Internal::Twirp::Classroom
  module AccessCheck
    module V1
      # Handler for the MonolithTwirp::Classroom::AccessCheck::V1::AccessCheckAPIService
      class AccessCheckAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["classroom"]
        handles_service MonolithTwirp::Classroom::AccessCheck::V1::AccessCheckAPIService

        # Public: Implementation of the BatchRepositoryCheck Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::AccessCheck::V1::BatchRepositoryCheckRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::AccessCheck::V1::BatchRepositoryCheckResponse, or a Twirp::Error.
        def batch_repository_check(req, env)
          unless req.access_token.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "access_token")
          end

          unless req.repository_ids.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_ids")
          end

          ac = Classroom::AccessControl.new(token: req.access_token)

          accessible, inaccessible = Repository.where(id: Array(req.repository_ids)).partition do |repository|
            ac.repository_accessible?(repository)
          end

          { accessible_repository_ids: accessible.map(&:id), inaccessible_repository_ids: inaccessible.map(&:id) }
        end

        # Public: Implementation of the HasRepositoryAccess Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::AccessCheck::V1::HasRepositoryAccessRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::AccessCheck::V1::HasRepositoryAccessResponse, or a Twirp::Error.
        def has_repository_access(req, env)
          unless id_argument(req.repository_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id")
          end

          unless req.access_token.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "access_token")
          end

          unless repository = ::Repositories.domain.by_id(req.repository_id)
            return Twirp::Error.not_found("Repository not found", argument: "repository_id")
          end

          ac = Classroom::AccessControl.new(token: req.access_token)
          { has_access: ac.repository_accessible?(repository) }
        end
      end
    end
  end
end
