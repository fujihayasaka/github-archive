# typed: true
# frozen_string_literal: true

require "dependency-graph-platform-proto"

module Api::Internal::Twirp::DependencyGraphPlatform
  module Repositories
    module V1
      class RepositoriesAPIHandler < Api::Internal::Twirp::Handler
        Proto = Github::DependencyGraphPlatform::GhInternal::Repositories::V1

        allow_access_for :client, allowed_clients: ["dependency_graph_platform"]
        handles_service Proto::RepositoriesAPIService

        sig do
          params(
            req: Proto::GetRepositoryStateRequest,
            env: T::Hash[String, T.untyped]
          ).returns(
            T.any(
              Proto::GetRepositoryStateResponse,
              Twirp::Error
            )
          )
        end
        def get_repository_state(req, env)
          unless req.repository_id.present? && req.repository_id.nonzero?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id")
          end

          repository = ::Repositories::Public.get_active_or_deleted(req.repository_id)
          return Twirp::Error.not_found("Repository ID '#{req.repository_id}' not found.") unless repository

          owner_type = if repository.owner_type == "Organization"
            Proto::GetRepositoryStateResponse::RepositoryOwnerType::ORG
          elsif repository.owner_type == "User"
            Proto::GetRepositoryStateResponse::RepositoryOwnerType::USER
          else
            Proto::GetRepositoryStateResponse::RepositoryOwnerType::UNKNOWN_REPOSITORY_OWNER_TYPE
          end

          visibility = case repository.visibility
          when "public"
            Proto::GetRepositoryStateResponse::RepositoryVisibility::PUBLIC
          when "private"
            Proto::GetRepositoryStateResponse::RepositoryVisibility::PRIVATE
          when "internal"
            Proto::GetRepositoryStateResponse::RepositoryVisibility::INTERNAL
          else
            Proto::GetRepositoryStateResponse::RepositoryVisibility::UNKNOWN_REPOSITORY_VISIBILITY
          end

          Proto::GetRepositoryStateResponse.new(
            repository_id: repository.id,
            owner_id: repository.owner_id,
            owner_type: owner_type,
            business_id: repository.business_id,
            visibility: visibility,
            default_branch: repository.default_branch,
            archived: repository.archived?,
            soft_delete_found_at: proto_timestamp(repository.deleted_at),
            created_at: proto_timestamp(repository.created_at),
            updated_at: proto_timestamp(repository.updated_at),
            parent_repository_id: repository.parent_id,
          )
        end

        private

        sig do
          params(time: T.nilable(ActiveSupport::TimeWithZone)).returns(Google::Protobuf::Timestamp)
        end
        def proto_timestamp(time)
          Google::Protobuf::Timestamp.new(seconds: time.to_i)
        end
      end
    end
  end
end
