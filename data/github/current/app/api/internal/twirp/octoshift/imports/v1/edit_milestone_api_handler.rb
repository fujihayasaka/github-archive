# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::EditMilestoneAPIService
      class EditMilestoneAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::ModelDelay
        include Imports::Helpers::ContentCreation
        include Helpers::ErrorHandler
        include Imports::Helpers::LiveMigrations

        allow_access_for :client, allowed_clients: %w[octoshift elm migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::EditMilestoneAPIService

        # Public: Implementation of the EditMilestone Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::EditMilestoneRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::EditMilestoneResponse, or a Twirp::Error.
        def edit_milestone(req, env)
          check_model_replication_delay!(Milestone)

          begin
            milestone = Milestone.find(req.id)
          rescue ActiveRecord::RecordNotFound
            return Twirp::Error.not_found("Milestone not found.", argument: "id", value: req.id.to_s, octoshift_error_code: "MILESTONE_NOT_FOUND")
          end

          case req.action
          when :LIVE_MIGRATION_ACTION_EDITED
            err = check_outdated_updated_at(milestone, req.updated_at)
            return err if err
            edit(milestone, req.title, req.description, req.state, req.due_on, req.closed_at, req.issue_ids, req.updated_at)
          when :LIVE_MIGRATION_ACTION_DELETED
            delete(milestone)
          else
            # This should never happen; if it does, the client is sending an invalid request.
            Twirp::Error.invalid_argument("Invalid LiveMigrationAction", argument: "action")
          end
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def edit(milestone, title, description, state, due_on, closed_at, issue_ids, updated_at)
          milestone.title = title
          milestone.description = description
          milestone.state = ImportMilestonesAPIHandler::MILESTONE_STATES[state]
          milestone.due_on = due_on&.to_time
          milestone.closed_at = closed_at&.to_time
          milestone.updated_at = updated_at&.to_time

          rate_limited_mode(milestone) do
            unless milestone.issue_ids.empty? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
              # Remove old issues from the milestone
              ImportableIssue.where(id: milestone.issue_ids.to_a).update_all(milestone_id: nil) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
            end
            unless issue_ids.empty?
              # Add new issues to the milestone
              ImportableIssue.where(id: issue_ids.to_a).update_all(milestone_id: milestone.id) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
            end

            unless milestone.save
              return Twirp::Error.canceled("Could not update milestone: #{milestone.errors.full_messages.join(", ")}.")
            end
          rescue Sequence::Error
            return Twirp::Error.failed_precondition("Request cannot be fulfilled due to error creating milestone sequence.", octoshift_error_code: "SEQUENCE_ERROR")
          end
          MonolithTwirp::Octoshift::Imports::V1::EditMilestoneResponse.new
        end

        def delete(milestone)
          rate_limited_mode(milestone) do
            # Can this be done in a transaction? (It doesn't need to be - worst case, we're left with an undeleted milestone,
            # and issues without a milestone, which is way better than a deleted milestone with issues still attached.)
            Issue.where(milestone_id: milestone.id).update_all(milestone_id: nil) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
            unless milestone.destroy
              return Twirp::Error.canceled("Could not destroy milestone: #{milestone.errors.full_messages.join(", ")}.")
            end
          end
          MonolithTwirp::Octoshift::Imports::V1::EditMilestoneResponse.new
        end
      end
    end
  end
end
