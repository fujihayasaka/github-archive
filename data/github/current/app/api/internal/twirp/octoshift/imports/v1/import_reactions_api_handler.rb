# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handles the creation of imported reactions.
      class ImportReactionsAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay
        include Imports::Helpers::Attribution

        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportReactionsAPIService
        allow_access_for :client, allowed_clients: ["octoshift"]

        CONTENT_MAP = {
          REACTION_CONTENT_THUMBS_UP: "+1",
          REACTION_CONTENT_THUMBS_DOWN: "-1",
          REACTION_CONTENT_LAUGH: "smile",
          REACTION_CONTENT_TADA: "tada",
          REACTION_CONTENT_CONFUSED: "thinking_face",
          REACTION_CONTENT_HEART: "heart",
          REACTION_CONTENT_ROCKET: "rocket",
          REACTION_CONTENT_EYES: "eyes"
        }.freeze

        SUBJECT_TYPE_MAP = {
          REACTION_SUBJECT_TYPE_COMMIT_COMMENT: "CommitComment",
          REACTION_SUBJECT_TYPE_DISCUSSION: "Discussion",
          REACTION_SUBJECT_TYPE_DISCUSSION_COMMENT: "DiscussionComment",
          REACTION_SUBJECT_TYPE_DISCUSSION_POST: "DiscussionPost",
          REACTION_SUBJECT_TYPE_DISCUSSION_POST_REPLY: "DiscussionPostReply",
          REACTION_SUBJECT_TYPE_ISSUE: "Issue",
          REACTION_SUBJECT_TYPE_ISSUE_COMMENT: "IssueComment",
          REACTION_SUBJECT_TYPE_PULL_REQUEST_REVIEW: "PullRequestReview",
          REACTION_SUBJECT_TYPE_PULL_REQUEST_REVIEW_COMMENT: "PullRequestReviewComment",
          REACTION_SUBJECT_TYPE_RELEASE: "Release",
          REACTION_SUBJECT_TYPE_REPOSITORY_ADVISORY: "RepositoryAdvisory",
          REACTION_SUBJECT_TYPE_REPOSITORY_ADVISORY_COMMENT: "RepositoryAdvisoryComment"
        }.freeze

        MAX_THROTTLE_RETRIES = 5

        # Public: Implementation of the ImportReactions Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportReactionsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportReactionsResponse, or a Twirp::Error.
        def import_reactions(req, env)
          write_reactions(req)
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def write_reactions(req)
          subject_type = SUBJECT_TYPE_MAP.fetch(req.subject_type)
          specific_reaction_type = ::Reactable::SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS.include?(subject_type)
          repository_id = replica(subject_type.constantize).find_by!(id: req.subject_id).repository_id if specific_reaction_type

          check_model_replication_delay!(reaction_type(subject_type))

          errors = []

          built_reactions = req.reactions.map.with_index do |reaction, index|
            begin
              user = find_user(reaction.user_login)
              content = CONTENT_MAP.fetch(reaction.content)

              if specific_reaction_type
                build_specific_reaction(
                  content: content,
                  subject_type: subject_type,
                  subject_id: req.subject_id,
                  repository_id: repository_id,
                  user: user,
                  created_at: reaction.created_at
                )
              else
                build_reaction(
                  content: content,
                  subject_type: subject_type,
                  subject_id: req.subject_id,
                  user: user,
                  created_at: reaction.created_at
                )
              end
            rescue Errors::InvalidReactionsError => error
              errors << { batch_index: index, error_message: error.message.msg }
              next
            end
          end.compact

          reaction_type(subject_type).throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            ActiveRecord::Base.connected_to(role: :writing) do
              reaction_type(subject_type).insert_all(built_reactions) unless built_reactions.empty?
            end
          end

          { reactions: [], batch_validation_errors: errors }

        rescue ActiveRecord::ActiveRecordError
          # Error message is sanitized to obscure architectural errors due to batch inserts
          Twirp::Error.malformed("Failed to insert reactions. Validation errors if any: #{errors}")
        end

        def reaction_type(subject_type)
          if ::Reactable::SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS.include?(subject_type)
            "#{subject_type}Reaction".constantize
          else
            Reaction
          end
        end

        def find_user(login)
          raise Errors::InvalidReactionsError, Twirp::Error.invalid_argument("user_login required for reaction.") if login.empty?

          find_mannequin_or_user_by_login!(login)
        rescue ActiveRecord::RecordNotFound
          raise Errors::InvalidReactionsError, Twirp::Error.invalid_argument("Couldn't find user with login #{login}.")
        end

        def build_reaction(content:, subject_type:, subject_id:, user:, created_at:)
          raise Errors::InvalidReactionsError, Twirp::Error.invalid_argument("created_at required for reaction.") unless created_at

          Reaction.new(
            content: content,
            subject_type: subject_type,
            subject_id: subject_id,
            user: user,
            created_at: created_at.to_time,
            updated_at: created_at.to_time
          ).attributes
        end

        def build_specific_reaction(content:, subject_type:, subject_id:, repository_id:, user:, created_at:)
          raise Errors::InvalidReactionsError, Twirp::Error.invalid_argument("created_at required for reaction.") unless created_at

          reaction_type_id = "#{subject_type.underscore}_id"

          attributes = reaction_type(subject_type).new(
            content: content,
            "#{reaction_type_id}": subject_id,
            user: user,
            repository_id: repository_id,
            created_at: created_at.to_time,
            updated_at: created_at.to_time
          ).attributes

          # moving content to be first so insert_all works with vitess - it can't be a vindexed key
          { "content" => content }.merge(attributes)
        end
      end
    end
  end
end
