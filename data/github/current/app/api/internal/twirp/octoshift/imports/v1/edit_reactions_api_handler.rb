# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::EditReactionsAPIService
      class EditReactionsAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay
        include Imports::Helpers::Attribution

        handles_service MonolithTwirp::Octoshift::Imports::V1::EditReactionsAPIService
        allow_access_for :client, allowed_clients: %w[elm migrations_vnext]

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

        DISCUSSION_SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS = Set.new(%w[
          Discussion
          DiscussionComment
        ]).freeze

        MAX_THROTTLE_RETRIES = 5

        # Public: Implementation of the EditReactions Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::EditReactionsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::EditReactionsResponse, or a Twirp::Error.
        def edit_reactions(req, env)
          error = validate(req)
          return error if error

          sync_reactions(req)
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def sync_reactions(req)
          subject_type = SUBJECT_TYPE_MAP.fetch(req.subject_type)
          reaction_model = reaction_type(subject_type)

          specific_reaction_type = ::Reactable::SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS.include?(subject_type)
          specific_discussion_reaction_type = DISCUSSION_SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS.include?(subject_type)
          repository_id = replica(subject_type.constantize).find_by!(id: req.subject_id).repository_id if specific_reaction_type

          check_model_replication_delay!(reaction_model)

          errors = []

          existing_reactions = if specific_reaction_type || specific_discussion_reaction_type
            reaction_model.where("#{subject_type.underscore}_id": req.subject_id).to_a
          else
            reaction_model.where(subject_type: subject_type, subject_id: req.subject_id).to_a
          end

          existing_reactions_hash = existing_reactions.index_by { |r| reaction_key(r.user.login, r.content, r.created_at) }

          incoming_reactions_hash = req.reactions.each_with_index.to_h do |reaction, index|
            key = reaction_key(reaction.user_login, CONTENT_MAP.fetch(reaction.content), reaction.created_at)
            [key, { reaction: reaction, index: index }]
          end

          to_add_keys = incoming_reactions_hash.keys - existing_reactions_hash.keys
          to_delete_keys = existing_reactions_hash.keys - incoming_reactions_hash.keys

          built_reactions = []
          to_add_keys.each do |key|
            reaction = incoming_reactions_hash[key][:reaction]
            index = incoming_reactions_hash[key][:index]

            begin
              user = find_user(reaction.user_login)
              content = CONTENT_MAP.fetch(reaction.content)

              if specific_reaction_type
                built = build_specific_reaction(
                  content: content,
                  subject_type: subject_type,
                  subject_id: req.subject_id,
                  repository_id: repository_id,
                  user: user,
                  created_at: reaction.created_at
                )
              elsif specific_discussion_reaction_type
                built = build_specific_discussion_reaction(
                  content: content,
                  subject_type: subject_type,
                  subject_id: req.subject_id,
                  user: user,
                  created_at: reaction.created_at
                )
              else
                built = build_reaction(
                  content: content,
                  subject_type: subject_type,
                  subject_id: req.subject_id,
                  user: user,
                  created_at: reaction.created_at
                )
              end

              built_reactions << built if built
            rescue Errors::InvalidReactionsError => error
              errors << { batch_index: index, error_message: error.message.msg }
            end
          end

          to_delete_ids = to_delete_keys.map { |key|  existing_reactions_hash[key].id }

          reaction_model.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            ActiveRecord::Base.connected_to(role: :writing) do
              reaction_model.transaction do
                reaction_model.where(id: to_delete_ids).delete_all unless to_delete_ids.empty?
                reaction_model.insert_all(built_reactions) unless built_reactions.empty?
              end
            end
          end

          { reactions: [], batch_validation_errors: errors }

        rescue ActiveRecord::ActiveRecordError
          # Error message is sanitized to obscure architectural errors due to batch inserts
          Twirp::Error.malformed("Failed to edit reactions. Validation errors if any: #{errors}")
        end

        def reaction_type(subject_type)
          if ::Reactable::SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS.include?(subject_type) || DISCUSSION_SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS.include?(subject_type)
            "#{subject_type}Reaction".constantize
          else
            Reaction
          end
        end

        def reaction_key(user_login, content, created_at)
          "#{user_login}|#{content}|#{created_at.to_i}"
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

        def build_specific_discussion_reaction(content:, subject_type:, subject_id:, user:, created_at:)
          raise Errors::InvalidReactionsError, Twirp::Error.invalid_argument("created_at required for reaction.") unless created_at

          subject = "#{subject_type}".constantize.find_by(id: subject_id)

          reaction_type(subject_type).new(
            content: content,
            "#{subject_type.underscore}": subject,
            user: user,
            created_at: created_at.to_time,
            updated_at: created_at.to_time
          ).attributes
        end

        def find_user(login)
          raise Errors::InvalidReactionsError, Twirp::Error.invalid_argument("user_login required for reaction.") if login.empty?

          find_mannequin_or_user_by_login!(login)
        rescue ActiveRecord::RecordNotFound
          raise Errors::InvalidReactionsError, Twirp::Error.invalid_argument("Couldn't find user with login #{login}.")
        end

        def validate(req)
          if req.action != :LIVE_MIGRATION_ACTION_EDITED
            return Twirp::Error.invalid_argument("must be a valid action", argument: "action")
          end

          if req.subject_id.negative? || req.subject_id.zero?
            return Twirp::Error.invalid_argument("must be a positive integer", argument: "subject_id")
          end

          if !SUBJECT_TYPE_MAP.key?(req.subject_type)
            return Twirp::Error.invalid_argument("must be a valid enum", argument: "subject_type")
          end

          nil
        end
      end
    end
  end
end
