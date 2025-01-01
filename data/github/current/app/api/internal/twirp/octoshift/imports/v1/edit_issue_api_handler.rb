# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::EditIssueAPIService
      class EditIssueAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::Attribution
        include Imports::Helpers::ContentCreation
        include Imports::Helpers::LiveMigrations
        include Imports::Helpers::ModelDelay
        include Helpers::ErrorHandler

        STATE_MAP = {
          EDIT_ISSUE_STATE_INVALID: "invalid",
          EDIT_ISSUE_STATE_OPEN: "open",
          EDIT_ISSUE_STATE_CLOSED: "closed"
        }.freeze

        allow_access_for :client, allowed_clients: %w[octoshift migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::EditIssueAPIService

        # Public: Implementation of the EditIssue Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::EditIssueRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::EditIssueResponse, or a Twirp::Error.
        def edit_issue(req, env)
          check_model_replication_delay!(ImportableIssue)

          # Validate args
          err = validate(req.id, req.action, req.updated_at, req.user_login, req.body&.value)
          return err if err

          issue = replica(ImportableIssue).find_by(id: req.id)
          unless issue
            return Twirp::Error.not_found("Issue '#{req.id}' was not found.")
          end

          unless Repository.active.where(id: issue.repository_id).exists?
            return Twirp::Error.not_found("Repository not found.", octoshift_error_code: "REPOSITORY_DELETED")
          end

          # Only update if the incoming updated_at is newer than the latest timestamp on the issue
          err = check_outdated_updated_at(issue, req.updated_at)
          return err if err

          rate_limited_mode(issue) do
            if req.action == :LIVE_MIGRATION_ACTION_EDITED
              return edit(issue, req.updated_at, req.user_login, req.title, req.body&.value, req.assignees, req.closed_at, req.state, req.labels)
            elsif req.action == :LIVE_MIGRATION_ACTION_DELETED
              return delete(issue)
            end
          end
        rescue Errors::UnableToEditError => error
          error.message
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def validate(id, action, updated_at, user_login, body)
          if id.negative? || id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "id")
          end
          if action == :LIVE_MIGRATION_ACTION_INVALID
            return Twirp::Error.invalid_argument("must be a valid enum", argument: "action")
          end

          return if action == :LIVE_MIGRATION_ACTION_DELETED

          if updated_at.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "updated_at")
          end
          if !body.nil? && user_login.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_login") # rubocop:disable Style/RedundantReturn
          end
        end

        def edit(issue, updated_at, user_login, title, body, assignees, closed_at, state, labels)
          if title.present? && issue.title != title
            issue.update(title: title) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
          end

          if !body.nil? && issue.body != body
            # Fetch the user who edited the issue
            user = user_or_ghost(user_login)
            raise Errors::UnableToEditError, Twirp::Error.not_found("User '#{user_login}' was not found.") unless user

            issue.update_body(body, user)
          end

          if issue.assignees.map(&:login).sort != assignees.sort
            edit_assignees(issue, assignees)
          end

          if state != :EDIT_ISSUE_STATE_INVALID && issue.state != STATE_MAP[state]
            edit_state(issue, state, closed_at)
          end

          if issue.labels.map(&:lowercase_name).sort != labels.map { |label| label.downcase }.sort
            edit_labels(issue, labels)
          end

          issue.update(updated_at: updated_at&.to_time) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)

          build_issue_hash(issue)
        end

        def edit_assignees(issue, assignees)
          assignee_map = build_user_map(assignees.to_a)

          issue.assignees.each do |assignee|
            next if assignees.include?(assignee.login)

            remove_assignee(issue, assignee)
          end

          assignees&.each do |assignee_login|
            assignee = assignee_map[assignee_login]
            next unless assignee

            add_assignee(issue, assignee)
          end
        end

        def remove_assignee(issue, assignee)
          assignment = Assignment.find_by(issue: issue, assignee: assignee)
          return unless assignment

          assignment.destroy # domain-isolation-query-violation:ignore:packages/issues (SELECT)

          issue.assignees.reload
        end

        def add_assignee(issue, assignee)
          return if issue.assignees.include?(assignee)

          assignment = Assignment.create({
            issue: issue,
            assignee: assignee,
            skip_trigger_assigned_event: true,
            skip_ensure_assignee_is_a_collaborator: true
          })
          return unless assignment.save

          issue.add_assignees(assignee)
          issue.save! # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
        end

        def edit_labels(issue, labels)
          issue.labels.each do |label|
            next if labels.map { |label| label.downcase }.include?(label.lowercase_name)

            issue.labels.delete(label)
          end

          labels.each do |label|
            next if issue.labels.find_by_name(label)

            new_label = issue.repository.labels.find_by_name(label) || Label.new(repository: issue.repository, name: label)
            issue.labels << new_label
          end
        end

        def edit_state(issue, state, closed_at)
          if state == :EDIT_ISSUE_STATE_OPEN
            state = "open"
            err = "Issue could not be opened"
          else
            state = "closed"
            err = "Issue could not be closed"
          end

          unless issue.update(state: state, closed_at: closed_at&.to_time) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
            raise Errors::UnableToEditError, Twirp::Error.canceled(err)
          end
        end

        def delete(issue)
          return build_issue_hash(issue) if issue.destroy # domain-isolation-query-violation:ignore:packages/issues (DELETE, SELECT)

          # If we could not destroy the model, return an error
          Twirp::Error.canceled("Issue could not be deleted")
        end

        def build_issue_hash(issue)
          {
            id: issue.id
          }
        end
      end
    end
  end
end
