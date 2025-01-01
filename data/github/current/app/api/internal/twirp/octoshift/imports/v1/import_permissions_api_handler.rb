# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::ImportPermissionsAPIService
      class ImportPermissionsAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay

        allow_access_for :client, allowed_clients: %w[octoshift migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportPermissionsAPIService

        # Public: Implementation of the ImportPermissions Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportPermissionsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportPermissionsResponse, or a Twirp::Error.
        def import_permissions(req, env)
          repository_id = req.repository_id

          if repository_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end

          if req.permissions.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "permissions")
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          return Twirp::Error.not_found("Repository not found", argument: "repository_id", value: repository_id.to_s, octoshift_error_code: "REPOSITORY_DELETED") unless repository && repository.active?

          errors = []

          req.permissions.each_with_index do |permission, index|
            if permission.role.empty?
              errors << { batch_index: index, error_message: "Role must be non-empty" }
              next
            end

            team = replica(Team).find_by(organization: repository.owner, name: permission.team_name)
            unless team.present?
              errors << { batch_index: index, error_message: "Team not found for #{permission.team_name}" }
              next
            end

            result = ActiveRecord::Base.connected_to(role: :writing) do
              team.add_repository(repository, permission.role)
            end

            unless result.status == :success
              errors << { batch_index: index, error_message: "Unable to add team #{permission.team_name} to repository" }
            end
          end

          { batch_validation_errors: errors }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end
      end
    end
  end
end
