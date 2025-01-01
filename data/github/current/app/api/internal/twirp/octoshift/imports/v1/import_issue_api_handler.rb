# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1

      class ImportIssueAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::ContentCreation
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay
        include Imports::Helpers::Attribution

        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportIssueAPIService
        allow_access_for :client, allowed_clients: ["octoshift"]

        # Public: Implementation of the ImportIssues Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportIssuesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportIssuesResponse, or a Twirp::Error.
        def import_issue(req, env)
          check_model_replication_delay!(ImportableIssue)

          if req.author_login.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "author_login")
          end
          if req.repository_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end
          if req.title.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "title")
          end
          if req.number.negative? || req.number.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "number")
          end
          if req.created_at.nil?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "created_at")
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          unless repository && repository.active?
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s, octoshift_error_code: "REPOSITORY_DELETED")
          end

          user = find_mannequin_or_user_by_login(req.author_login)
          unless user
            return Twirp::Error.not_found("User not found.", argument: "author_login", value: req.author_login.to_s)
          end

          assignee_map = build_user_map(req.assignees.to_a)

          return already_exists_error_handler("Issue") if already_exists?(req.number, repository.id)

          issue = ImportableIssue.new(
            repository: repository,
            user: user,
            created_at: req.created_at.to_time,
            closed_at: req.closed_at&.to_time,
            updated_at: req.updated_at&.to_time,
            title: req.title,
            body: req.body,
            number: req.number,
            state: req.closed_at.nil? ? "open" : "closed"
          )

          rate_limited_mode(issue) do
            unless issue.save
              return save_model_error_handler(issue)
            end
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            req.assignees&.each do |assignee_login|
              assignee = assignee_map[assignee_login]
              unless assignee
                next
              end

              Assignment.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES, skip_reporting: true) do
                assignment = Assignment.create({
                  issue: issue,
                  assignee: assignee,
                  skip_trigger_assigned_event: true,
                  skip_ensure_assignee_is_a_collaborator: true
                })
                unless assignment.save
                  next
                end
              end
            end
          end

          {
            issue: {
              id: issue.id,
              number: issue.number
            }
          }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def already_exists?(number, repository_id)
          replica(Issue).query do |klass|
            klass.where(number: number, repository_id: repository_id).exists?
          end
        end
      end
    end
  end
end
