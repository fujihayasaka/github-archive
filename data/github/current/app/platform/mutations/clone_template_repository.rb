# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CloneTemplateRepository < Platform::Mutations::Base
      description "Create a new repository with the same files and directory structure as a " \
                  "template repository."

      def self.async_api_can_modify?(permission, repository:, owner:, visibility:, **inputs)
        owner ||= permission.viewer
        private_repo = visibility == ::Repository::PRIVATE_VISIBILITY

        if owner.organization?
          permission.access_allowed?(private_repo ? :create_private_repo_for_org : :create_repo_for_org,
            resource: owner,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
            current_repo: nil,
            current_org: owner,
          )
        else
          permission.async_owner_if_org(repository).then do |org|
            permission.access_allowed?(private_repo ? :create_private_repo : :create_repo,
              resource: repository,
              repo: repository,
              current_org: org,
              allow_integrations: true,
              allow_user_via_granular_actor: true)
          end
        end
      end

      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, "The Node ID of the template repository.", required: true,
        loads: Objects::Repository
      argument :name, String, "The name of the new repository.", required: true
      argument :owner_id, ID, "The ID of the owner for the new repository.", required: true,
        loads: Interfaces::RepositoryOwner
      argument :description, String, "A short description of the new repository.", required: false
      argument :visibility, Enums::RepositoryVisibility,
        "Indicates the repository's visibility level.", required: true
      argument :include_all_branches, Boolean,
        "Whether to copy all branches from the template to the new repository. " \
        "Defaults to copying only the default branch of the template.",
        required: false, default_value: false

      field :repository, Objects::Repository, "The new repository.", null: true

      def resolve(repository:, name:, owner:, visibility:, description: nil, include_all_branches: false)
        reflog_data = {
          real_ip: context[:rails_request]&.remote_ip,
          # login is ok when used for internal logs
          user_login: context[:viewer].login, # rubocop:disable GitHub/DoNotAllowLogin
          user_agent: context[:user_agent],
          from: GitHub.context[:from],
          via: "template repository clone",
        }

        new_repository, reason, message = repository.clone_template_to(owner,
          actor: context[:viewer],
          name: name,
          copy_branches: include_all_branches,
          description: description,
          visibility: visibility,
          reflog_data: reflog_data,
          current_integration_context: build_current_integration_context(target: owner, entry_point: :graphql_api_clone_template_repository_mutation)
        )

        if reason == :forbidden
          raise Errors::Forbidden, message
        end

        if reason == :unprocessable_entity
          raise Errors::Unprocessable, message
        end

        { repository: new_repository }
      end

      def build_current_integration_context(target:, entry_point:)
        permission = context[:permission]
        { integration: permission.integration, entry_point: entry_point } if permission.integration_bot_or_user_request?
      end
    end
  end
end
