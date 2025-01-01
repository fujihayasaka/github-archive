# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveContentWarnings < Platform::Mutations::Base
      description "Remove content warnings from repositories."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :repository_ids, [ID], "Global relay IDs of repositories whose content warnings will be removed.", required: true, loads: Objects::Repository, as: :repositories
      argument :forks, Boolean, "Remove content warnings from repository forks too.", required: false, default_value: false

      argument :async, Boolean, "Whether or not to run operation in a background job. Should always be set to true. Is an arg for sake of backward compatibility.", required: false, default_value: false

      field :forks, Boolean, "Whether or not content warnings were removed from forks.", null: true
      field :successes, [Objects::Repository], "The repositories from which content warnings were removed (not including forks).", null: true
      field :failures, [Objects::Repository], "The repositories from which content warnings failed to be removed (not including forks).", null: true
      field :errors, [String], "The errors that caused `failures`.", null: true

      def self.async_api_can_modify?(permission, **_)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      def resolve(repositories:, forks:, async:)
        response = { forks: forks, successes: [], failures: [], errors: [] }

        if async
          repositories.each do |repo|
            begin
              repo.set_content_warning(nil, actor: context[:actor], forks: forks)
              response[:successes].append(repo)
            rescue TrustSafety::ContentWarnings::ValidationError => error
              response[:failures].append(repo)
              response[:errors].append(error.message)
            end
          end
        else # Synchronous execution is deprecated and should not be invoked: https://github.com/github/github/pull/331559
          repositories.each do |repo|
            begin
              repo.set_content_warning(nil, actor: context[:actor], forks: forks)
              response[:successes].append(repo)
            rescue TrustSafety::ContentWarnings::ValidationError => error
              response[:failures].append(repo)
              response[:errors].append(error.message)
            end
          end
        end

        response
      end
    end
  end
end
