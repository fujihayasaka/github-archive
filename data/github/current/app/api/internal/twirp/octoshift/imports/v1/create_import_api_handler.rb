# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handles the creation of import data.
      class CreateImportAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay

        handles_service MonolithTwirp::Octoshift::Imports::V1::CreateImportAPIService
        allow_access_for :client, allowed_clients: ["octoshift"]

        # Public: Implementation of the CreateImport Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::CreateImportRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::CreateImportResponse, or a Twirp::Error.
        def create_import(req, env)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id") if req.user_id == 0

          user = replica(User).find_by(id: req.user_id)
          return Twirp::Error.not_found("User was not found.") unless user

          import = Import.new({ creator: user })

          ActiveRecord::Base.connected_to(role: :writing) do
            if import.save
              { import: build_import_hash(import) }
            else
              Twirp::Error.canceled("Could not create import: #{import.errors.full_messages.join(", ")}")
            end
          end
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def build_user_hash(user)
          {
            id: user.id,
            login: user.login,
            name: user.name
          }
        end

        # Private: Convert the import object to the Twirp response
        # CreateImportResponse.
        #
        # import - The import object.
        #
        # Returns an Hash object with import data that matches the
        # Twirp definition.
        def build_import_hash(import)
          {
            id: import.id,
            creator: build_user_hash(import.creator)
          }
        end
      end
    end
  end
end
