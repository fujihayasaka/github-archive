# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V2
      # Handler for the MonolithTwirp::Octoshift::Imports::V2::ImportIssueCommentsAPIService
      class ImportIssueCommentsAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::Attribution
        include Imports::Helpers::ContentCreation
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay

        allow_access_for :client, allowed_clients: ["octoshift"]
        handles_service MonolithTwirp::Octoshift::Imports::V2::ImportIssueCommentsAPIService

        # Public: Implementation of the ImportIssueComments Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V2::ImportIssueCommentsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V2::ImportIssueCommentsResponse, or a Twirp::Error.
        def import_issue_comments(req, env)
          check_model_replication_delay!(ImportableIssueComment)

          if req.issue_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "issue_id")
          end

          if req.transformed_issue_comments.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "transformed_issue_comments")
          end

          issue = replica(ImportableIssue).find_by(id: req.issue_id)

          return Twirp::Error.not_found("Issue '#{req.issue_id}' was not found.") unless issue
          return Twirp::Error.not_found("Repository not found.", octoshift_error_code: "REPOSITORY_DELETED") unless Repository.active.where(id: issue.repository_id).exists?

          first_error = validate_issue_comments(req.transformed_issue_comments)
          return first_error if first_error

          imported_issue_comments = []
          errors = []

          req.transformed_issue_comments.each do |issue_comment_to_import|
            user = user_or_ghost(issue_comment_to_import.author_login)
            unless user
              errors << build_error_hash(
                resource_identifier: issue_comment_to_import.resource_identifier,
                message: "User '#{issue_comment_to_import.author_login}' was not found.",
                twirp_error_code: "not_found"
              )

              next
            end

            if check_for_duplicate(issue, user.id, issue_comment_to_import.created_at.to_time)
              errors << build_error_hash(
                resource_identifier: issue_comment_to_import.resource_identifier,
                message: "IssueComment attempted to load, but already exists",
                twirp_error_code: "already_exists",
                octoshift_error_code: "ALREADY_EXISTS"
              )

              next
            end

            issue_comment = ImportableIssueComment.new(
              user: user,
              issue: issue,
              body: issue_comment_to_import.body,
              created_at: issue_comment_to_import.created_at.to_time,
            )

            rate_limited_mode(issue_comment) do
              if issue_comment.save
                imported_issue_comments << [issue_comment, issue_comment_to_import.resource_identifier]
              else
                errors << save_model_error_handler(issue_comment, issue_comment_to_import.resource_identifier)
              end
            end
          end

          build_response_hash(imported_issue_comments, errors)
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def build_issue_comment_hash(issue_comment, resource_identifier)
          {
            id: issue_comment.id,
            resource_identifier: resource_identifier
          }
        end

        def check_for_duplicate(issue, user_id, created_at)
          replica(IssueComment).query do |klass|
            klass.where(issue: issue, user_id: user_id, created_at: created_at).exists?
          end
        end

        # Validates all transformed_issue_comments and returns the first validation error as a Twirp::Error or else returns nil
        def validate_issue_comments(transformed_issue_comments)
          transformed_issue_comments.each do |issue_comment|
            if issue_comment.resource_identifier.empty?
              return Twirp::Error.invalid_argument(
                "resource_identifier must be non empty",
                argument: "transformed_issue_comments"
              )
            end

            if issue_comment.body.empty?
              return Twirp::Error.invalid_argument(
                "body must be non empty",
                argument: "transformed_issue_comments",
                resource_identifier: issue_comment.resource_identifier
              )
            end

            if issue_comment.created_at.blank?
              return Twirp::Error.invalid_argument(
                "created_at must be non empty",
                argument: "transformed_issue_comments",
                resource_identifier: issue_comment.resource_identifier
              )
            end
          end

          nil
        end

        def build_response_hash(imported_issue_comments, errors)
          {
            issue_comments: imported_issue_comments.map { |issue_comment, resource_identifier| build_issue_comment_hash(issue_comment, resource_identifier) },
            errors: errors
          }
        end
      end
    end
  end
end
