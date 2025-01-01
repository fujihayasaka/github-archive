# typed: true
# frozen_string_literal: true

require "monolith-twirp-licensing-repositories"

module Api::Internal::Twirp::Licensing
  module Repositories
    module V1
      # Handler for the MonolithTwirp::Licensing::Repositories::V1::RepositoriesAPIService
      class RepositoriesAPIHandler < Api::Internal::Twirp::Handler
        include Scientist

        allow_access_for :client, allowed_clients: ["licensing"]
        handles_service MonolithTwirp::Licensing::Repositories::V1::RepositoriesAPIService

        # Public: Implementation of the GetRepositoryInformation Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Licensing::Repositories::V1::GetRepositoryInformationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Licensing::Repositories::V1::GetRepositoryInformationResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Licensing::Repositories::V1::GetRepositoryInformationRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(T.any(MonolithTwirp::Licensing::Repositories::V1::GetRepositoryInformationResponse, Twirp::Error))
        end
        def get_repository_information(req, env)
          unless repo_id = id_argument(req.id)
            return Twirp::Error.invalid_argument("id is required", argument: "id")
          end

          repo = T.cast(::Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
          unless repo
            return Twirp::Error.not_found("repository not found")
          end

          ::Failbot.push "gh.repository.id": repo.id

          repository = MonolithTwirp::Licensing::Repositories::V1::Repository.new(
            id: repo.id,
            visibility: handle_visibility(repo.visibility),
            parent_id: repo.parent_id,
            is_fork: repo.fork?,
            is_advisory_workspace: repo.advisory_workspace?,
            is_active: repo.active?,
            owner_customer_id: Licensing::Customer.id_for(repo),
          )

          MonolithTwirp::Licensing::Repositories::V1::GetRepositoryInformationResponse.new(
            repository: repository,
            collaborator_ids: req.include_collaborators ? get_collaborator_ids(repo) : [],
          )
        end

        # Public: Implementation of the GetRepositoryVisibilities Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Licensing::Repositories::V1::GetRepositoryVisibilitiesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Licensing::Repositories::V1::GetRepositoryVisibilitiesResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Licensing::Repositories::V1::GetRepositoryVisibilitiesRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(T.any(MonolithTwirp::Licensing::Repositories::V1::GetRepositoryVisibilitiesResponse, Twirp::Error))
        end
        def get_repository_visibilities(req, env)
          repo_ids = req.ids.to_a

          if FeatureFlag.vexi.enabled?(:get_repository_vis_no_large_in_candidate, default: false)
            repos = ::Repositories.domain.by_ids(repo_ids, include_internal_repository: true, batch_size: GH::Domain::Base::MAX_REPOSITORY_ID_IN_CLAUSE_SIZE)
          else
            repos = science "get_repository_vis_no_large_in" do |e|
              e.try { ::Repositories.domain.by_ids(repo_ids, include_internal_repository: true, batch_size: GH::Domain::Base::MAX_REPOSITORY_ID_IN_CLAUSE_SIZE) }
              e.use { Repository.includes(:internal_repository).where(id: repo_ids).active }
              e.compare_record_sequence
            end
          end

          repository_infos = repos.map do |repo|
            ::Failbot.push "gh.repository.id": repo.id

            MonolithTwirp::Licensing::Repositories::V1::GetRepositoryVisibilitiesResponse::RepositoryInfo.new(
              id: repo.id,
              visibility: handle_visibility(repo.visibility),
            )
          end

          MonolithTwirp::Licensing::Repositories::V1::GetRepositoryVisibilitiesResponse.new(
            repositories: repository_infos,
          )
        end

        private

        def handle_visibility(visibility)
          case visibility.to_sym
          when :public
            MonolithTwirp::Licensing::Repositories::V1::Repository::Visibility::VISIBILITY_PUBLIC
          when :private
            MonolithTwirp::Licensing::Repositories::V1::Repository::Visibility::VISIBILITY_PRIVATE
          when :internal
            MonolithTwirp::Licensing::Repositories::V1::Repository::Visibility::VISIBILITY_INTERNAL
          else
            MonolithTwirp::Licensing::Repositories::V1::Repository::Visibility::VISIBILITY_INVALID
          end
        end

        sig { params(repo: Repository).returns(T::Array[Integer]) }
        def get_collaborator_ids(repo)
          return [] if repo.advisory_workspace? || repo.fork? || repo.public? || !repo.active?

          ::Ability.from("abilities FORCE INDEX(subject_and_actor_and_priority_and_action)")
            .where(
                subject_id: repo.id,
                subject_type: "Repository",
                actor_type: "User",
                priority: Ability.priorities[:direct],
              ).distinct
            .pluck(:actor_id)
        end
      end
    end
  end
end
