# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateRepository < Platform::Mutations::Base
      description "Update information about a repository."

      def self.async_api_can_modify?(permission, repository:, **inputs)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(:edit_repo, resource: repository, repo: repository,
                                     current_org: org, allow_integrations: true,
                                     allow_user_via_granular_actor: true)
        end
      end

      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, "The ID of the repository to update.", required: true,
        loads: Objects::Repository
      argument :name, String, "The new name of the repository.", required: false
      argument :description, String,
        "A new description for the repository. Pass an empty string to erase the existing description.", required: false
      argument :template, Boolean, "Whether this repository should be marked as a template " \
                                   "such that anyone who can access it can create new " \
                                   "repositories with the same files and directory structure.", required: false
      argument :homepage_url, Scalars::URI, "The URL for a web page about this repository. Pass an empty string to erase the existing URL.",
        required: false
      argument :has_wiki_enabled, Boolean,
        "Indicates if the repository should have the wiki feature enabled.",
        required: false
      argument :has_issues_enabled, Boolean,
        "Indicates if the repository should have the issues feature enabled.",
        required: false
      argument :has_projects_enabled, Boolean,
        "Indicates if the repository should have the project boards feature enabled.",
        required: false
      argument :has_discussions_enabled, Boolean,
        "Indicates if the repository should have the discussions feature enabled.",
        required: false
      argument :has_sponsorships_enabled, Boolean,
        "Indicates if the repository displays a Sponsor button for financial contributions.",
        required: false,
        visibility: {
          internal: { environments: [:enterprise] },
          public: { environments: [:dotcom] },
        }

      field :repository, Objects::Repository, "The updated repository.", null: true

      def resolve(repository:, name: nil, description: nil,
                  has_projects_enabled: nil, template: nil, homepage_url: nil,
                  has_wiki_enabled: nil, has_issues_enabled: nil, has_discussions_enabled: nil,
                  has_sponsorships_enabled: nil)
        repository.validate_description_length = true
        updater = Repository::Updater.new(repository,
          actor: context[:viewer],
          name: name,
          template: template,
          description: description,
          has_issues: has_issues_enabled,
          homepage: homepage_url,
          has_wiki: has_wiki_enabled,
          has_projects: has_projects_enabled,
          has_discussions: has_discussions_enabled,
          has_sponsorships: has_sponsorships_enabled,
        )
        if updater.update
          { repository: repository }
        else
          raise Errors::Unprocessable.new(updater.error)
        end
      end
    end
  end
end
