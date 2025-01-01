# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handles the creation of imported milestones.
      class ImportMilestonesAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::ContentCreation
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay
        include Imports::Helpers::Attribution
        include Imports::Helpers::AlreadyExists

        MILESTONE_STATES = {
          MILESTONE_STATE_INVALID: nil,
          MILESTONE_STATE_OPEN: :open,
          MILESTONE_STATE_CLOSED: :closed
        }.freeze

        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportMilestonesAPIService
        allow_access_for :client, allowed_clients: %w[octoshift migrations_vnext]

        # Public: Implementation of the ImportMilestones Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportMilestonesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportMilestonesResponse, or a Twirp::Error.
        def import_milestones(req, env)
          check_model_replication_delay!(Milestone)

          if req.repository_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end
          if req.milestones.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "milestones")
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          unless repository && repository.active?
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s, octoshift_error_code: "REPOSITORY_DELETED")
          end

          milestone_mappings_response = []
          already_exists_errors = []

          req.milestones.each do |milestone_request|
            if milestone_request.source_id.zero?
              return Twirp::Error.invalid_argument("must be positive integer", argument: "source_id")
            end
            if milestone_request.title.empty?
              return Twirp::Error.invalid_argument("must be non-empty", argument: "title")
            end
            if milestone_request.created_by_user_login.empty?
              return Twirp::Error.invalid_argument("must be non-empty", argument: "created_by_user_login")
            end

            created_by_user = find_mannequin_or_user_by_login(milestone_request.created_by_user_login)
            unless created_by_user
              return Twirp::Error.not_found("User not found.", argument: "created_by_user_login", value: milestone_request.created_by_user_login.to_s)
            end

            # If this feature flag is disabled, we allow the old behavior, which allows attributing issues to a milestone
            # even if the milestone already exists. (This was to allow octoshift to do bulk imports of milestones, which might
            # time out and thus need retrying.)
            #
            # If this feature flag is enabled, we disallow the old behavior, and instead require that the client (currently octoshift,
            # soon also Migrations VNext/ELM) use the EditMilestoneAPI to edit an existing milestone.
            if !FeatureFlag.vexi.enabled?("octoshift_ops__disallow_milestone_import_api_edit", default: false)
              # If milestone has already been created, skip importing it but still return milestone mapping
              milestone = replica(Milestone).query do |klass|
                klass.where(title: milestone_request.title, repository_id: req.repository_id).first
              end

              unless milestone
                milestone = Milestone.new(
                  repository: repository,
                  title: milestone_request.title,
                  created_by: created_by_user,
                  description: milestone_request.description,
                  state: MILESTONE_STATES[milestone_request.state],
                  due_on: milestone_request.due_on&.to_time&.utc, # due_on truncates to midnight, so use utc to get proper date
                  created_at: milestone_request.created_at&.to_time,
                  updated_at: milestone_request.updated_at&.to_time
                )

                rate_limited_mode(milestone) do
                  begin
                    unless milestone.save
                      return Twirp::Error.canceled("Could not create milestone: #{milestone.errors.full_messages.join(", ")}.")
                    end
                  rescue Sequence::Error
                    return Twirp::Error.failed_precondition("Request cannot be fulfilled due to error creating milestone sequence.", octoshift_error_code: "SEQUENCE_ERROR")
                  end
                end
              end
            # This branch is for the new behavior, that does not allow edits; because check_for_existing_record!
            # raises an error, we don't need to guard against the code below being run in that scenario.
            else
              # will raise AlreadyExists if a record with the same title already exists; we rescue below
              # and push the id mapping into the response
              check_for_existing_record!(Milestone, title: milestone_request.title, repository_id: req.repository_id)

              milestone = Milestone.new(
                repository: repository,
                title: milestone_request.title,
                created_by: created_by_user,
                description: milestone_request.description,
                state: MILESTONE_STATES[milestone_request.state],
                due_on: milestone_request.due_on&.to_time&.utc, # due_on truncates to midnight, so use utc to get proper date
                created_at: milestone_request.created_at&.to_time,
                updated_at: milestone_request.updated_at&.to_time
              )

              rate_limited_mode(milestone) do
                begin
                  unless milestone.save
                    return Twirp::Error.canceled("Could not create milestone: #{milestone.errors.full_messages.join(", ")}.")
                  end
                rescue Sequence::Error
                  return Twirp::Error.failed_precondition("Request cannot be fulfilled due to error creating milestone sequence.", octoshift_error_code: "SEQUENCE_ERROR")
                end
              end
            end

            unless milestone_request.issue_ids.empty?
              milestone_updated_at = milestone.updated_at

              ActiveRecord::Base.connected_to(role: :writing) do
                ImportableIssue.where(id: milestone_request.issue_ids.to_a).find_each do |issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
                  issue.milestone = milestone
                  unless issue.save # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
                    next
                  end
                end

                milestone.touch(time: milestone_updated_at) if milestone
              end
            end

            # Milestone by default calls set_closed_at before saving which overrides
            # the closed_at to Time.now if it's closed. We update the closed_at after
            # saving to ensure the right value is set.
            if milestone.closed?
              ActiveRecord::Base.connected_to(role: :writing) do
                milestone.update_column(:closed_at, milestone_request.closed_at&.to_time)
              end
            end

            milestone_mappings_response.push(
              {
                id: milestone.id,
                source_id: milestone_request.source_id
              }
            )
          rescue Api::Internal::Twirp::Octoshift::Errors::AlreadyExists => already_exists_error
            mapping = {
              id: already_exists_error.existing_record_id,
              source_id: milestone_request.source_id
            }
            milestone_mappings_response.push(mapping)
            already_exists_errors.push(mapping)
          end

          {
            milestone_mappings: milestone_mappings_response,
            already_exists_errors: already_exists_errors
          }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end
      end
    end
  end
end
