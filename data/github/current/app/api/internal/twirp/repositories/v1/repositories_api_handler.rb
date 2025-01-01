# typed: true
# frozen_string_literal: true

require "monolith-twirp-github-repositories"

class Api::Internal::Twirp < ::Api::Internal
  module Repositories
    module V1

      # Provides access to Repository data.
      class RepositoriesAPIHandler < Api::Internal::Twirp::Handler
        handles_service(MonolithTwirp::GitHub::Repositories::V1::RepositoriesAPIService)

        allow_access_for :user, :client, allowed_clients: %w(spokesd launch helphub token_scanning_service dependency_graph_api goproxy git_src_migrator copilot_api actions_usage_metrics).freeze

        FIND_REPOSITORIES_HARD_LIMIT = 100

        # Public: Implementation of the FindRepositories Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Repositories::V1::FindRepositoriesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of repositories, suitable for use in
        # a GitHub::Proto::Repositories::V1::FindRepositoriesResponse.
        def find_repositories(req, env)
          if req.ids.empty?
            Twirp::Error.invalid_argument("must be non-empty", argument: "ids")
          elsif req.ids.size > FIND_REPOSITORIES_HARD_LIMIT
            Twirp::Error.invalid_argument("must have a length <= #{FIND_REPOSITORIES_HARD_LIMIT}", argument: "ids")
          else
            # req.ids is a Google::Protobuf::RepeatedField,
            # and we need to call #to_a to get a value usable
            # by ActiveRecord.
            scope = Repository.where(id: req.ids.to_a).preload(:owner)
            {
              repositories: build_repository_list(scope)
            }
          end
        end

        # Public: Implementation of the FindRepositoriesByName Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Repositories::V1::FindRepositoriesByNameRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of repositories, suitable for use in
        # a GitHub::Proto::Repositories::V1::FindRepositoriesByNameResponse.
        #
        # TODO: document what happens for a non-existent nwo: Zero or -1 in result slot?
        #  Empty result? Failed RPC?
        def find_repositories_by_name(req, env)
          if req.nwos.empty?
            Twirp::Error.invalid_argument("must be non-empty", argument: "nwos")
          elsif req.nwos.size > FIND_REPOSITORIES_HARD_LIMIT
            Twirp::Error.invalid_argument("must have a length <= #{FIND_REPOSITORIES_HARD_LIMIT}", argument: "nwos")
          else
            # TODO: opt: use a single database lookup, not a sequence of them.
            repositories = req.nwos.to_a.map do |repo_nwo|
              Repository.with_name_with_owner(repo_nwo) ||
                RepositoryRedirect.find_redirected_repository(repo_nwo)
            end

            # TODO: is this necessary?
            return {} if repositories.none?

            {
              repositories: build_repository_list(repositories)
            }
          end
        end

        # Public: Implementation of the FindRepositoryPermissions Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Repositories::V1::FindRepositoryPermissions.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of repositories, suitable for use in
        # a GitHub::Proto::Repositories::V1::FindRepositoryPermissionsResponse.
        def find_repository_permissions(req, env)
          user_id = id_argument(req.user_id, env[:user_id])
          if req.repository_ids.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_ids")
          elsif req.repository_ids.size > FIND_REPOSITORIES_HARD_LIMIT
            return Twirp::Error.invalid_argument("must have a length <= #{FIND_REPOSITORIES_HARD_LIMIT}", argument: "repository_ids")
          elsif user_id.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          elsif (user = User.find_by(id: user_id)).nil?
            return Twirp::Error.not_found("user does not exist", argument: "user_id")
          end

          repositories = Repository.where(id: req.repository_ids.to_a)
          {
            repositories: build_repository_permissions_list(repositories, user)
          }
        end

        private

        # Private: Gets the status of the repository.
        #
        # Returns an enum.
        def get_repository_status(repository)
          return :STATUS_ARCHIVED if repository.archived?
          return :STATUS_SPAMMY if GitHub.spamminess_check_enabled? && repository.spammy?
          return :STATUS_DISABLED if repository.disabled? || repository.access.tos_violation? || repository.access.abusive?
          return :STATUS_ACTIVE if repository.active?

          :STATUS_INVALID
        end

        # Private: Gets the visibility of the repository.
        #
        # Returns an enum.
        def get_repository_visibility(repository)
          if repository.public?
            :VISIBILITY_PUBLIC
          elsif repository.private? && repository.visibility == Repository::PRIVATE_VISIBILITY
            :VISIBILITY_PRIVATE
          elsif repository.internal?
            :VISIBILITY_INTERNAL
          else
            :VISIBILITY_INVALID
          end
        end

        # Private: Gets the access permissions a user has on a repository.
        #
        # repository - Repository object.
        # user - User object.
        #
        # Returns an enum.
        def get_user_repository_permission(repository, user)
          case repository.access_level_for(user)
          when nil
            :USER_PERMISSION_NO_ACCESS
          when :read
            :USER_PERMISSION_READ
          when :write
            :USER_PERMISSION_WRITE
          when :admin
            :USER_PERMISSION_ADMIN
          else
            :USER_PERMISSION_INVALID
          end
        end

        # Private: Convert an array of Repository objects to the Twirp response FindRepositoriesResponse.
        #
        # repositories - The array of Repository objects.
        #
        # Returns an array of Hash objects with repository data that matches the
        # Twirp definition.
        def build_repository_list(repositories)
          repositories.map do |repository|
            next {} unless repository
            {
              id: repository.id,
              owner_id: repository.owner&.id,
              name: repository.name,
              owner_login: repository.owner&.login,
              status: get_repository_status(repository),
              visibility: get_repository_visibility(repository)
            }
          end
        end

        # Private: Convert an array of Repository objects to the Twirp response FindRepositoryPermissions.
        #
        # repositories - The array of Repository objects.
        # User - User object.
        #
        # Returns an array of Hash objects with repository data that matches the
        # Twirp definition.
        def build_repository_permissions_list(repositories, user)
          repositories.map do |repository|
            {
              id: repository.id,
              name: repository.name,
              user_permission: get_user_repository_permission(repository, user)
            }
          end
        end
      end
    end
  end
end
