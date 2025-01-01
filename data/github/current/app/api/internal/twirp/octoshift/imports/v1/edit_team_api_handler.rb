# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::EditTeamAPIService
      class EditTeamAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::ModelDelay
        include Imports::Helpers::ContentCreation
        include Imports::Helpers::LiveMigrations
        include Helpers::ErrorHandler

        allow_access_for :client, allowed_clients: %w[elm migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::EditTeamAPIService

        # Public: Implementation of the EditTeam Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::EditTeamRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::EditTeamResponse, or a Twirp::Error.
        def edit_team(req, env)
          check_model_replication_delay!(Team)

          begin
            team = Team.find(req.id)
          rescue ActiveRecord::RecordNotFound
            return Twirp::Error.not_found("Team not found.", argument: "id", value: req.id.to_s, octoshift_error_code: "TEAM_NOT_FOUND")
          end

          case req.action
          when :LIVE_MIGRATION_ACTION_EDITED
            err = check_outdated_updated_at(team, req.updated_at)
            return err if err

            # Note: inconsistency between Ruby models and Twirp request/response objects in name/team_name and
            # privacy/visibility, are a holdover from the ImportTeamAPIHandler.
            team.name = req.team_name
            team.description = req.team_description&.value
            team.parent_team_id = req.parent_team_id&.value
            team.privacy = req.visibility
            team.updated_at = req.updated_at&.to_time

            rate_limited_mode(team) do
              unless team.save
                return Twirp::Error.canceled("Could not update team: #{team.errors.full_messages.join(", ")}.")
              end
            end
            MonolithTwirp::Octoshift::Imports::V1::EditTeamResponse.new
          when :LIVE_MIGRATION_ACTION_DELETED
            rate_limited_mode(team) do
              unless team.destroy
                return Twirp::Error.canceled("Could not destroy team: #{team.errors.full_messages.join(", ")}.")
              end
            end
            MonolithTwirp::Octoshift::Imports::V1::EditTeamResponse.new
          else
            # This should never happen; if it does, the client is sending an invalid request.
            Twirp::Error.invalid_argument("Invalid LiveMigrationAction", argument: "action")
          end
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end
      end
    end
  end
end
