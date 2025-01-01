# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::ImportMigrationLogAPIService
      class ImportMigrationLogAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay

        allow_access_for :client, allowed_clients: %w[octoshift elm migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportMigrationLogAPIService

        # Public: Implementation of the ImportMigrationLog Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportMigrationLogRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportMigrationLogResponse, or a Twirp::Error.
        def import_migration_log(req, env)
          if req.log_data.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "log_data")
          end

          if req.owner_login.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "owner_login")
          end
          if req.repository_name.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_name")
          end

          if req.migration_id.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "migration_id")
          end
          org_name = req.owner_login
          repo_name = req.repository_name
          migration_id = req.migration_id

          log_storage_helper = Octoshift::Service::LogStorageHelper.new
          migration_log_error = nil
          download_url = nil

          begin
            log_name = "#{repo_name}-#{migration_id}"
            log_storage_helper.upload_repo_log(org_name, log_name, req.log_data)
            download_url = log_storage_helper.get_repo_log_url(org_name, log_name)
          rescue Octoshift::Service::LogStorageHelper::UploadError, Octoshift::Service::LogStorageHelper::GenerateUrlError, Octoshift::Service::LogStorageHelper::MissingCredentialsError => e
            migration_log_error = e.message
          end

          { migration_log_url: download_url, migration_log_error: migration_log_error }
        end
      end
    end
  end
end
