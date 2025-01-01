# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::EditLabelAPIService
      class EditLabelAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::ModelDelay
        include Imports::Helpers::ContentCreation
        include Imports::Helpers::LiveMigrations
        include Helpers::ErrorHandler

        allow_access_for :client, allowed_clients: %w[elm migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::EditLabelAPIService

        # Public: Implementation of the EditLabel Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::EditLabelRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::EditLabelResponse, or a Twirp::Error.
        def edit_label(req, env)
          check_model_replication_delay!(Label)

          repo_id = req.repository_id
          return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id") if req.repository_id.zero?

          repository = ::Repositories.domain.by_id(repo_id)
          if repository.nil?
            return Twirp::Error.not_found("repository not found", argument: "repository_id", value: repo_id.to_s, octoshift_error_code: "REPOSITORY_NOT_FOUND")
          elsif repository.deleted?
            return Twirp::Error.not_found("repository deleted", argument: "repository_id", value: repo_id.to_s, octoshift_error_code: "REPOSITORY_DELETED")
          end

          begin
            label = Label.find_by!(repository: repository, name: req.name)
          rescue ActiveRecord::RecordNotFound
            return Twirp::Error.not_found("label not found.", argument: "name", value: req.name, octoshift_error_code: "LABEL_NOT_FOUND")
          end

          case req.action
          when :LIVE_MIGRATION_ACTION_EDITED
            return Twirp::Error.invalid_argument("must be non-empty", argument: "updated_at") if req.updated_at.blank?

            err = check_outdated_updated_at(label, req.updated_at)
            return err if err

            label.name = req.new_name&.value
            label.color = req.color&.value
            if req.description
              desc = req.description&.value
              label.description = desc unless desc.nil?
            end
            label.updated_at = Time.now

            rate_limited_mode(label) do
              unless label.save
                return Twirp::Error.canceled("Could not update label: #{label.errors.full_messages.join(", ")}.")
              end
            end
            MonolithTwirp::Octoshift::Imports::V1::EditLabelResponse.new
          when :LIVE_MIGRATION_ACTION_DELETED
            rate_limited_mode(label) do
              unless label.destroy
                return Twirp::Error.canceled("Could not destroy label: #{label.errors.full_messages.join(", ")}.")
              end
            end
            MonolithTwirp::Octoshift::Imports::V1::EditLabelResponse.new
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
