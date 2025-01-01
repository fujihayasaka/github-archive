# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::ImportTeamAPIService
      class ImportTeamAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Helpers::ContentCreation

        allow_access_for :client, allowed_clients: ["octoshift"]
        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportTeamAPIService

        # Public: Implementation of the ImportTeam Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportTeamRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportTeamResponse, or a Twirp::Error.
        def import_team(req, env)
          if req.target_org_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "target_org_id")
          end

          if req.team_name.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "team_name")
          end

          team = Team.new(
            organization_id: req.target_org_id,
            name: req.team_name,
            privacy: req.visibility,
            description: req.team_description&.value,
          )

          team.parent_team_id = req.parent_team_id&.value if req.parent_team_id.present?

          rate_limited_mode(team) do
            unless team.save
              return save_model_error_handler(team)
            end
          end

          { id: team.id }
        end
      end
    end
  end
end
