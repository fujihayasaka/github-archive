# typed: true
# frozen_string_literal: true

require "monolith-twirp-elm-actions"

module Api::Internal::Twirp::Elm
  module Actions
    module V1
      class ImportCommitStatusCheckAPIHandler < Api::Internal::Twirp::Handler
        handles_service MonolithTwirp::Elm::Actions::V1::ImportCommitStatusCheckAPIService

        # Allow access for internal services and authorized ELM Actions clients
        allow_access_for :client, allowed_clients: %w[elm migrations_vnext]

        # Import a commit status check
        #
        # @param req [MonolithTwirp::Elm::Actions::V1::ImportCommitStatusCheckRequest] The import request
        # @param env [Hash] The Twirp environment
        # @return [Hash] The import response hash
        # Public: Implementation of the ImportCommitStatusCheck Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Elm::Actions::V1::ImportCommitStatusCheckRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash or a Twirp::Error.
        def import_commit_status_check(req, env)
          # Validate repository_id is present
          repo_id = req.repository_id
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") if repo_id.nil? || repo_id == 0

          # Find and validate the repository
          repository = Repository.find_by(id: repo_id)
          if repository.nil?
            return Twirp::Error.not_found("Repository not found", argument: "repository_id", value: repo_id.to_s, elm_error_code: "REPOSITORY_NOT_FOUND")
          elsif repository.deleted?
            return Twirp::Error.not_found("Repository deleted", argument: "repository_id", value: repo_id.to_s, elm_error_code: "REPOSITORY_DELETED")
          end

          # Validate commit_status_checks array
          if req.commit_status_checks.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "commit_status_checks")
          end

          # Use batch processing for better performance
          process_batch_import(repository, req.commit_status_checks)
        rescue ArgumentError, ActiveRecord::RecordInvalid => e
          # Handle expected domain exceptions
          GitHub.logger.error("Import commit status check validation error: #{e.message}")
          Twirp::Error.invalid_argument(e.message)
        rescue => e # rubocop:disable Style/RescueStandardError,Lint/GenericRescue
          # Handle unexpected errors to prevent 500s
          GitHub.logger.error("Import commit status check unexpected error: #{e.message}")
          Twirp::Error.internal("An unexpected error occurred")
        end

        private

        def process_batch_import(repository, status_checks)
          # Validate and prepare status attributes for batch import
          valid_status_attributes = []
          failed_checks = []

          # Preload all required users in a single query to avoid n+1 queries
          creator_ids = status_checks.map(&:creator_id).uniq
          users_by_id = User.where(id: creator_ids).index_by(&:id)

          status_checks.each do |status_check|
            validation_result = validate_status_check(status_check)

            if validation_result[:valid]
              # Map protobuf state to Status model state
              state = map_protobuf_state_to_status_state(status_check.state)

              if state.nil?
                failed_checks << build_failed_check_response(status_check, "invalid state")
                next
              end

              # Check for existing status to prevent duplicates
              domain = Statuses::Domain.new
              if domain.status_exists?(repository_id: repository.id, sha: status_check.commit_sha, context: status_check.context)
                failed_checks << build_failed_check_response(status_check, "status check already exists")
                next
              end

              creator = users_by_id[status_check.creator_id]
              valid_status_attributes << {
                sha: status_check.commit_sha,
                state: state,
                context: status_check.context,
                creator: creator,
                description: status_check.description&.empty? ? nil : status_check.description,
                target_url: status_check.target_url&.empty? ? nil : status_check.target_url,
                oauth_application_id: nil, # Could be extended to support this in the future
                source_resource_id: status_check.source_resource_id
              }
            else
              failed_checks << build_failed_check_response(status_check, validation_result[:error])
            end
          end

          created_checks = []

          # Perform batch import if we have valid statuses
          if valid_status_attributes.any?
            begin
              domain = Statuses::Domain.new
              domain.batch_import(
                repository_id: repository.id,
                status_attributes: valid_status_attributes,
                batch_size: 100  # Conservative batch size that works well with Vitess
              )

              # Build created checks response from the valid attributes
              # Since batch_import can't return the created records since it's using raw SQL rather than ActiveRecord,
              # we'll use source_resource_id to track these
              valid_status_attributes.each do |attrs|
                created_checks << {
                  source_resource_id: attrs[:source_resource_id],
                  commit_sha: attrs[:sha],
                  context: attrs[:context]
                }
              end
            rescue ArgumentError, ActiveRecord::RecordInvalid => e
              # Report all valid statuses that failed to import
              valid_status_attributes.each do |attrs|
                failed_checks << {
                  source_resource_id: attrs[:source_resource_id],
                  commit_sha: attrs[:sha],
                  context: attrs[:context],
                  error_message: "Failed to save: #{e.message}"
                }
              end
            end
          end

          {
            success: failed_checks.empty?,
            created_commit_status_checks: created_checks,
            failed_commit_status_checks: failed_checks
          }
        end

        def validate_status_check(status_check)
          errors = []

          errors << "commit_sha must be non-empty" if status_check.commit_sha.blank?
          errors << "context must be non-empty" if status_check.context.blank?

          # Check state by attempting to map it
          if status_check.state.nil? || map_protobuf_state_to_status_state(status_check.state).nil?
            errors << "state must be non-empty"
          end

          # Check creator_id in proper order
          if status_check.creator_id.nil? || status_check.creator_id == 0
            errors << "creator_id must be provided"
          elsif !User.exists?(id: status_check.creator_id)
            errors << "creator_id must reference an existing user"
          end

          if errors.any?
            { valid: false, error: errors.join(", ") }
          else
            { valid: true }
          end
        end

        def build_failed_check_response(status_check, error_message)
          {
            source_resource_id: status_check.source_resource_id,
            commit_sha: status_check.commit_sha,
            context: status_check.context,
            error_message: error_message
          }
        end

        def map_protobuf_state_to_status_state(protobuf_state)
          case protobuf_state
          when :IMPORT_COMMIT_STATUS_CHECK_STATE_SUCCESS
            "success"
          when :IMPORT_COMMIT_STATUS_CHECK_STATE_FAILURE
            "failure"
          when :IMPORT_COMMIT_STATUS_CHECK_STATE_PENDING
            "pending"
          when :IMPORT_COMMIT_STATUS_CHECK_STATE_ERROR
            "error"
          else
            nil
          end
        end
      end
    end
  end
end
