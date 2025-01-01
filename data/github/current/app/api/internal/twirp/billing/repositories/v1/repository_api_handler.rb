# typed: true
# frozen_string_literal: true

require "monolith-twirp-billing-repositories"


module Api::Internal::Twirp::Billing
  module Repositories
    module V1
      class RepositoryAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["billing"]
        handles_service MonolithTwirp::Billing::Repositories::V1::RepositoryAPIService

        def get_repository_metadata(req, env)
          return Twirp::Error.invalid_argument("id is required") if req.id.blank? || req.id.zero?

          repository = ::Repositories::Public.get_active_or_deleted(req.id)
          return Twirp::Error.not_found("Repository #{req.id} not found") unless repository

          MonolithTwirp::Billing::Repositories::V1::GetRepositoryMetadataResponse.new(
            repository: {
              id: repository.id,
              is_public: repository.public,
            }
          )
        end

        def get_repository_visibilities(req, env)
          return Twirp::Error.invalid_argument("repo ids is required") if req.ids.empty?

          repo_ids = req.ids.to_a
          repos = Repository.includes(:internal_repository)
            .select(:id, :source_id, :public)
            .where(id: repo_ids)

          repository_infos = repos.map do |repo|
            MonolithTwirp::Billing::Repositories::V1::GetRepositoryVisibilitiesResponse::RepositoryVisibilityInfo.new(
              id: repo.id,
              visibility: handle_visibility(repo.visibility),
            )
          end

          MonolithTwirp::Billing::Repositories::V1::GetRepositoryVisibilitiesResponse.new(
            repositories: repository_infos,
          )
        end

        private

        def handle_visibility(visibility)
          case visibility.to_sym
          when :public
            MonolithTwirp::Billing::Repositories::V1::RepositoryVisibility::PUBLIC
          when :private
            MonolithTwirp::Billing::Repositories::V1::RepositoryVisibility::PRIVATE
          when :internal
            MonolithTwirp::Billing::Repositories::V1::RepositoryVisibility::INTERNAL
          else
            MonolithTwirp::Billing::Repositories::V1::RepositoryVisibility::VISIBILITY_UNKNOWN
          end
        end
      end
    end
  end
end
