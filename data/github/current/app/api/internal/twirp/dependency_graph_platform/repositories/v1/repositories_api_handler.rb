# typed: true
# frozen_string_literal: true

require "monolith-twirp-dependency_graph_platform-repositories"

module Api::Internal::Twirp::DependencyGraphPlatform
  module Repositories
    module V1
      class RepositoriesAPIHandler < Api::Internal::Twirp::Handler
        Proto = Github::DependencyGraphPlatform::GhInternal::Repositories::V1

        allow_access_for :client, allowed_clients: ["dependency_graph_platform"]
        handles_service Proto::RepositoriesAPIService

        MAX_LIMIT = 10_000

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
            Proto::GetRepositoryStateResponse::RepositoryOwnerType::REPOSITORY_OWNER_TYPE_ORG
          elsif repository.owner_type == "User"
            Proto::GetRepositoryStateResponse::RepositoryOwnerType::REPOSITORY_OWNER_TYPE_USER
          else
            Proto::GetRepositoryStateResponse::RepositoryOwnerType::REPOSITORY_OWNER_TYPE_INVALID
          end

          visibility = case repository.visibility
          when "public"
            Proto::GetRepositoryStateResponse::RepositoryVisibility::REPOSITORY_VISIBILITY_PUBLIC
          when "private"
            Proto::GetRepositoryStateResponse::RepositoryVisibility::REPOSITORY_VISIBILITY_PRIVATE
          when "internal"
            Proto::GetRepositoryStateResponse::RepositoryVisibility::REPOSITORY_VISIBILITY_INTERNAL
          else
            Proto::GetRepositoryStateResponse::RepositoryVisibility::REPOSITORY_VISIBILITY_INVALID
          end

          soft_found_deleted_at = if repository.deleted_at
            proto_timestamp(repository.deleted_at)
          else
            nil
          end

          Proto::GetRepositoryStateResponse.new(
            repository_id: repository.id,
            owner_id: repository.owner_id,
            owner_type: owner_type,
            business_id: repository.business_id,
            visibility: visibility,
            default_branch: repository.default_branch,
            archived: repository.archived?,
            soft_delete_found_at: soft_found_deleted_at,
            created_at: proto_timestamp(repository.created_at),
            updated_at: proto_timestamp(repository.updated_at),
            parent_repository_id: repository.parent_id,
            name_with_display_owner: repository.name_with_display_owner,
            instance_url: GitHub.url,
            repository_license: repository.license&.spdx_id,
          )
        end

        sig do
          params(
            req: Proto::ListRepositoriesRequest,
            env: T::Hash[String, T.untyped]
          ).returns(
            T.any(
              Proto::ListRepositoriesResponse,
              Twirp::Error
            )
          )
        end
        def list_repositories(req, env)
          unless GitHub.multi_tenant_enterprise?
            return Twirp::Error.unimplemented("ListRepositories is only supported in proxima environments")
          end

          limit = req.limit.nil? || req.limit == 0 ? MAX_LIMIT : req.limit.clamp(1, MAX_LIMIT)

          query = Repository.order(:id)
          query = query.where("id >= ?", req.cursor) unless req.cursor.nil? || req.cursor == 0

          ids = query.limit(limit).pluck(:id)

          Proto::ListRepositoriesResponse.new(
            repository_ids: ids,
            next_cursor: next_cursor(ids, limit)
          )
        end

        private

        sig do
          params(time: T.nilable(ActiveSupport::TimeWithZone)).returns(Google::Protobuf::Timestamp)
        end
        def proto_timestamp(time)
          Google::Protobuf::Timestamp.new(seconds: time.to_i)
        end

        sig do
          params(data: T.nilable(T::Array[Integer]), limit: Integer).returns(Integer)
        end
        def next_cursor(data, limit)
          return 0 unless data
          if data.size < limit
            0
          else
            last_id = data.last
            last_id ? (last_id + 1) : 0
          end
        end
      end
    end
  end
end
