# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handles the creation of an imported issue comment.
      class ImportIssueCommentAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::Attribution
        include Helpers::ContentCreation
        include Helpers::ErrorHandler
        include Helpers::ModelDelay

        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportIssueCommentAPIService
        allow_access_for :client, allowed_clients: ["octoshift"]

        # Public: Implementation of the ImportIssueComment Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportIssueCommentRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportIssueCommentResponse, or a Twirp::Error.
        def import_issue_comment(req, env)
          check_model_replication_delay!(ImportableIssueComment)

          if req.body.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "body")
          end
          if req.issue_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "issue_id")
          end
          if req.created_at.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "created_at")
          end

          issue = replica(ImportableIssue).find_by(id: req.issue_id)

          return Twirp::Error.not_found("Issue '#{req.issue_id}' was not found.") unless issue

          return Twirp::Error.not_found("Repository not found.", octoshift_error_code: "REPOSITORY_DELETED") unless Repository.active.where(id: issue.repository_id).exists?

          user = user_or_ghost(req.author_login)
          return Twirp::Error.not_found("User '#{req.author_login}' was not found.") unless user

          # Querying on `user_id` and `created_at` compound index for issue comments.
          return already_exists_error_handler("IssueComment") if check_for_duplicate(issue, user.id, req.created_at.to_time)

          issue_comment = ImportableIssueComment.new(
            user: user,
            issue: issue,
            body: req.body,
            created_at: req.created_at.to_time,
          )

          rate_limited_mode(issue_comment) do
            if issue_comment.save
              {
                issue_comment: build_issue_comment_hash(issue_comment)
              }
            else
              return save_model_error_handler(issue_comment)
            end
          end
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def build_issue_comment_hash(issue_comment)
          {
            id: issue_comment.id
          }
        end

        def check_for_duplicate(issue, user_id, created_at)
          replica(IssueComment).query do |klass|
            klass.where(issue: issue, user_id: user_id , created_at: created_at).exists?
          end
        end
      end
    end
  end
end
