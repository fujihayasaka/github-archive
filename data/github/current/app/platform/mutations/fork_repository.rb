# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ForkRepository < Platform::Mutations::Base
      description "Fork a repository"

      def self.async_api_can_modify?(permission, owner: nil, **inputs)
        owner ||= permission.viewer
        if owner.organization?
          permission.access_allowed?(:create_fork,
            resource: inputs[:parent_repository],
            allow_integrations: false,
            allow_user_via_granular_actor: false,
            current_repo: nil,
            current_org: owner
          )
        else
          permission.access_allowed?(:create_fork,
            resource: inputs[:parent_repository],
            allow_integrations: false,
            allow_user_via_granular_actor: false,
            current_repo: nil,
            current_org: nil,
          )
        end
      end

      mobile_only true

      minimum_accepted_scopes ["repo"]

      argument :parent_repository_id, ID, "The ID of the repository to fork", required: true, loads: Objects::Repository
      argument :owner_id, ID, "The ID of the owner for the new repository.", required: false, loads: Interfaces::RepositoryOwner
      argument :name, String, "When forking from an existing repository, a new name for the fork.", required: false
      argument :description, String, "When forking from an existing repository, a new description for the fork.", required: false
      argument :default_branch_only, Boolean, "When forking from an existing repository, fork with only the default branch.", required: false, default_value: true

      field :repository, Objects::Repository, "The new forked repository.", null: true

      def resolve(parent_repository:, **inputs)
        if parent_repository.empty?
          raise Errors::Unprocessable.new("The repository is empty and cannot be forked.")
        end

        if parent_repository.forking_disabled?
          raise Errors::Unprocessable.new("Forking is not allowed for this repository.")
        end

        owner = inputs[:owner] || context[:viewer]

        if parent_repository.private? && owner.organization? && !owner.allow_private_repository_forking?
          raise Errors::Unprocessable.new("Forking private repositories is not allowed for this organization.")
        end

        name = inputs[:name] || parent_repository.name
        description = inputs[:description] || parent_repository.description
        default_branch_only = inputs[:default_branch_only]

        options = {
          forker: context[:viewer],
          owner: owner,
          description: description,
          new_name: name,
          one_branch: default_branch_only
        }

        forked_repository, reason, errors = parent_repository.fork(options)

        if !forked_repository
          message = Repository::ForkerMethods.message_from_reason(reason, errors)
          raise Errors::Unprocessable.new(message)
        end

        { repository: forked_repository }
      end
    end
  end
end
