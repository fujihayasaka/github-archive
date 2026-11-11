# typed: strict
# frozen_string_literal: true

module Platform
  module Mutations
    class RemovePullRequestCreationCapBypassUsers < Platform::Mutations::Base
      docs_category :pulls
      read_arguments_from_replicas!(enable_selective_writes: true)
      read_mutation_fields_from_replicas!(ApplicationRecord::Repositories)

      SIZE_LIMIT = 100

      description "Remove users from the pull request creation cap bypass list. " \
                  "Only repository admins can manage the bypass list."

      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, "The Node ID of the repository.", required: true, loads: Objects::Repository
      argument :user_ids, [ID], "The Node IDs of the users to remove from the bypass list.", required: true, loads: Objects::User, as: :users

      field :repository, Objects::Repository, "The repository with the updated bypass list.", null: true

      sig do
        params(
          permission: Platform::Authorization::Permission,
          repository: ::Repository,
          inputs: T.untyped
        ).returns(Promise[T::Boolean])
      end
      def self.async_api_can_modify?(permission, repository:, **inputs)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(:edit_repo, resource: repository, repo: repository,
                                     current_org: org, allow_integrations: true,
                                     allow_user_via_granular_actor: true)
        end
      end

      sig { params(repository: ::Repository, users: T::Array[::User]).returns(T::Hash[Symbol, ::Repository]) }
      def resolve(repository:, users:)
        unless FeatureFlag.vexi.enabled?(:pull_request_creation_cap_allowlist_via_api, repository, default: false)
          raise Errors::Forbidden.new("The pull request creation cap allowlist feature is not enabled for this repository.")
        end

        if users.size > SIZE_LIMIT
          raise Errors::Unprocessable.new("Request exceeded limit of #{SIZE_LIMIT} users")
        end

        with_write(clusters: [ApplicationRecord::IssuesPullRequests]) do
          config = PullRequestCreationConfig.new(repository)
          config.remove_pull_request_creation_cap_bypass_users(users: users)
        end

        { repository: repository }
      end
    end
  end
end
