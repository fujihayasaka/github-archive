# typed: true
# frozen_string_literal: true

require "monolith-twirp-support-helphub"

module Api::Internal::Twirp::Support
  module HelpHub
    module V1
      # Provides access to Support-relevant repository context
      class RepositoriesSupportAPIHandler < Api::Internal::Twirp::Handler
        handles_service(MonolithTwirp::Support::HelpHub::V1::RepositoriesSupportAPIService)

        allow_access_for :user, :client, allowed_clients: %w(spokesd launch helphub token_scanning_service support_ops).freeze

        FIND_REPOSITORIES_HARD_LIMIT = 100

        # Public: Implementation of the FindRepositories Twirp RPC.
        #
        # req - The Twirp request as a HelpHub::V1::FindRepositoriesRequest
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of repositories, suitable for use in
        # a HelpHub::V1::FindRepositoriesResponse.
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
        # req - The Twirp request as a HelpHub::V1::FindRepositoriesByNameRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of repositories, suitable for use in
        # a HelpHub::V1::FindRepositoriesByNameResponse.
        def find_repositories_by_name(req, env)
          if req.nwos.empty?
            Twirp::Error.invalid_argument("must be non-empty", argument: "nwos")
          elsif req.nwos.size > FIND_REPOSITORIES_HARD_LIMIT
            Twirp::Error.invalid_argument("must have a length <= #{FIND_REPOSITORIES_HARD_LIMIT}", argument: "nwos")
          else
            repositories = req.nwos.to_a.map do |repo_nwo|
              Repository.with_name_with_owner(repo_nwo)
            end

            return {} if repositories.none?

            {
              repositories: build_repository_list(repositories)
            }
          end
        end

        # Public: Implementation of the FindRepositoryPermissions Twirp RPC.
        #
        # req - The Twirp request as a HelpHub::V1::FindRepositoryPermissions.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of repositories, suitable for use in
        # a HelpHub::V1::FindRepositoryPermissionsResponse.
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

          ActiveRecord::Base.connected_to(role: :reading) do
            repositories = Repository.where(id: req.repository_ids.to_a)
            {
              repositories: build_repository_permissions_list(repositories, user)
            }
          end
        end

        private

        # Private: Gets the status of the repository.
        #
        # Returns an enum.
        def get_repository_status(repository)
          return :REPOSITORY_STATUS_ARCHIVED if repository.archived?
          return :REPOSITORY_STATUS_SPAMMY if GitHub.spamminess_check_enabled? && repository.spammy?
          return :REPOSITORY_STATUS_DISABLED if repository.disabled? || repository.access.tos_violation? || repository.access.abusive?
          return :REPOSITORY_STATUS_ACTIVE if repository.active?

          :STATUS_INVALID
        end

        # Private: Gets the visibility of the repository.
        #
        # Returns an enum.
        def get_repository_visibility(repository)
          if repository.public?
            :REPOSITORY_VISIBILITY_PUBLIC
          elsif repository.private? && repository.visibility == Repository::PRIVATE_VISIBILITY
            :REPOSITORY_VISIBILITY_PRIVATE
          elsif repository.internal?
            :REPOSITORY_VISIBILITY_INTERNAL
          else
            :REPOSITORY_VISIBILITY_INVALID
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
            :REPOSITORY_USER_PERMISSION_NO_ACCESS
          when :read
            :REPOSITORY_USER_PERMISSION_READ
          when :write
            :REPOSITORY_USER_PERMISSION_WRITE
          when :admin
            :REPOSITORY_USER_PERMISSION_ADMIN
          else
            :REPOSITORY_USER_PERMISSION_INVALID
          end
        end

        # Private: Get fork root hash (if the repository is part of a fork network)
        def get_repository_fork_root(repository)
          {
            id: repository.id,
            owner_id: repository.owner&.id,
            name: repository.name,
            owner_login: repository.owner&.login
          }
        end

        # Private: Get repository fork hash (if the repository is part of a fork network)
        def get_repository_fork(repository)

          return nil unless repository.network_count.positive?
          {
            is_root: repository.network_root? && repository.parent_id.nil?,
            has_child_networks: repository.forks_count.positive?,
            has_parent_networks: repository.parent_id.present?,
            root: repository.network_root? ? nil : get_repository_fork_root(repository.root)
          }
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
              visibility: get_repository_visibility(repository),
              fork: get_repository_fork(repository)
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
