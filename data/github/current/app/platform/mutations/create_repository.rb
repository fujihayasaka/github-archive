# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateRepository < Platform::Mutations::Base
      extend T::Sig

      include Repositories::Domain::Provider

      description "Create a new repository."

      def self.async_api_can_modify?(permission, owner: nil, visibility:, **inputs)
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
          permission.access_allowed?(private_repo ? :create_private_repo : :create_repo,
            resource: owner,
            allow_integrations: false,
            allow_user_via_granular_actor: true,
            current_repo: nil,
            current_org: nil,
          )
        end
      end

      minimum_accepted_scopes ["public_repo"]

      argument :name, String, "The name of the new repository.", required: true
      argument :owner_id, ID, "The ID of the owner for the new repository.", required: false,
        loads: Interfaces::RepositoryOwner
      argument :description, String, "A short description of the new repository.", required: false
      argument :visibility, Enums::RepositoryVisibility,
        "Indicates the repository's visibility level.", required: true
      argument :template, Boolean, "Whether this repository should be marked as a template " \
                                   "such that anyone who can access it can create new " \
                                   "repositories with the same files and directory structure.", required: false, default_value: false
      argument :homepage_url, Scalars::URI, "The URL for a web page about this repository.",
        required: false
      argument :has_wiki_enabled, Boolean,
        "Indicates if the repository should have the wiki feature enabled.",
        required: false, default_value: false
      argument :has_issues_enabled, Boolean,
        "Indicates if the repository should have the issues feature enabled.",
        required: false, default_value: true
      argument :team_id, ID, "When an organization is specified as the owner, this ID identifies the team that should be granted access to the new repository.", required: false, loads: Objects::Team

      field :repository, Objects::Repository, "The new repository.", null: true

      def resolve(name:, owner: nil, visibility:, description: nil, template: false,
                  homepage_url: nil, has_wiki_enabled: false, has_issues_enabled: true, team: nil)
        repo_attributes = Repositories::CreateRepositoryAttributes.new(
          owner: owner,
          name: T.cast(name, String),
          description: T.cast(description, T.nilable(String)),
          visibility: Repositories::RepositoryVisibility.deserialize(visibility),
          template: T.cast(template, T::Boolean),
          homepage: T.cast(homepage_url, T.nilable(Addressable::URI)),
          has_wiki: T.cast(has_wiki_enabled, T::Boolean),
          has_issues: T.cast(has_issues_enabled, T::Boolean),
          team_id: T.cast(team&.id, T.nilable(Integer)),
        )

        integration_context = build_current_integration_context(target: owner, entry_point: :graphql_api_create_repository_mutation)

        case result = repositories_domain.create(repo_attributes, integration_context:)
        when GH::Result::Ok
          { repository: result.value }
        when GH::Result::Error::AccessDenied
          raise Errors::Forbidden.new(result.message)
        when GH::Result::Error::Validation
          errors = result.model.errors
          if errors[:base].first == GitHub::RateLimitedCreation::ERROR_MESSAGE
            raise Errors::RateLimited.new("You have created too many repositories, too quickly. Please try again later.")
          else
            error = errors.full_messages.join(", ").presence || result.message
            raise Errors::Unprocessable.new(error)
          end
        when GH::Result::Error
          raise Errors::Unprocessable.new(result.message)
        end
      end

      sig { override.returns(T.nilable(GH::Auth::Actor)) }
      def domain_actor
        context[:viewer]
      end

      def build_current_integration_context(target:, entry_point:)
        permission = context[:permission]
        { integration: permission.integration, entry_point: entry_point } if permission.integration_bot_or_user_request?
      end
    end
  end
end
