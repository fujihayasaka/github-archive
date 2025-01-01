# typed: true
# frozen_string_literal: true

require "monolith-twirp-elm-repositories"

module Api::Internal::Twirp::Elm
  module Repositories
    module V1
      # Handler for the MonolithTwirp::Elm::Repositories::V1::ExportRepositoryTopicsAPIService
      class ExportRepositoryTopicsAPIHandler < Api::Internal::Twirp::Handler
        handles_service MonolithTwirp::Elm::Repositories::V1::ExportRepositoryTopicsAPIService
        allow_access_for :client, allowed_clients: %w[elm migrations_vnext]

        # Public: Implementation of the ExportRepositoryTopics Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Elm::Repositories::V1::ExportRepositoryTopicsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Elm::Repositories::V1::ExportRepositoryTopicsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Elm::Repositories::V1::ExportRepositoryTopicsRequest,
            env: T::Hash[Symbol, T.untyped]
          ).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error))
        end
        def export_repository_topics(req, env)
          repo_id = req.repository_id
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") if repo_id == 0

          repository = if FeatureFlag.vexi.enabled?(:repos_by_id_api_twirp, default: false)
            T.cast(::Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
          else
            Repository.find_by(id: repo_id)
          end
          if repository.nil?
            return Twirp::Error.not_found("Repository not found", argument: "repository_id").tap do |error|
              error.meta[:value] = repo_id.to_s
              error.meta[:elm_error_code] = "REPOSITORY_NOT_FOUND"
            end
          elsif repository.deleted?
            return Twirp::Error.not_found("Repository deleted", argument: "repository_id").tap do |error|
              error.meta[:value] = repo_id.to_s
              error.meta[:elm_error_code] = "REPOSITORY_DELETED"
            end
          end

          build_export_response(repository.repository_topics)
        end

        def build_export_response(topics)
          {
            repository_topics: topics.map do |repo_topic|
              {
                name: repo_topic.topic_name,
                url: repo_topic.topic.try(:url),
                creator_resource_id: GitHub::Resources::UrlForModel.new(repo_topic.user).url,
                state: map_state_to_protobuf_enum(repo_topic.state),
                created_at: { seconds: repo_topic.created_at.to_i, nanos: 0 },
                updated_at: { seconds: repo_topic.updated_at.to_i, nanos: 0 }
              }
            end
          }
        end

        sig { params(state: String).returns(T.nilable(Symbol)) }
        def map_state_to_protobuf_enum(state)
          case state
          when "created"
            :REPOSITORY_TOPIC_STATE_CREATED
          when "suggested"
            :REPOSITORY_TOPIC_STATE_SUGGESTED
          when "declined_not_relevant"
            :REPOSITORY_TOPIC_STATE_DECLINED_NOT_RELEVANT
          when "declined_too_specific"
            :REPOSITORY_TOPIC_STATE_DECLINED_TOO_SPECIFIC
          when "declined_personal_preference"
            :REPOSITORY_TOPIC_STATE_DECLINED_PERSONAL_PREFERENCE
          when "declined_too_general"
            :REPOSITORY_TOPIC_STATE_DECLINED_TOO_GENERAL
          end
        end
      end
    end
  end
end
