# typed: false # rubocop:disable Sorbet/TrueSigil
# frozen_string_literal: true

module Platform::Objects::Query::Advisories
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  included do
    field :repository_advisory, Objects::RepositoryAdvisory, description: "Fetch a Repository Security Advisory by its GHSA ID", null: true do
      visibility :internal

      argument :owner, String, "The login field of a user or organization", required: true
      argument :name, String, "The name of the repository", required: true
      argument :ghsa_id, String, "GitHub Security Advisory ID.", required: true
    end

    def repository_advisory(owner:, name:, ghsa_id:)
      Platform::Helpers::RepositoryByNwo.async_repository_with_owner(
        permission: @context[:permission],
        viewer: @context[:viewer],
        login: owner,
        name: name,
        follow_repo_redirect: true,
      ).then do |repo|
        if repo
          Objects::RepositoryAdvisory.load_from_global_id(ghsa_id).then do |advisory|
            if advisory.repository_id == repo.id
              @context[:permission].typed_can_see?("RepositoryAdvisory", advisory).then do |advisory_readable|
                advisory_readable ? advisory : Promise.resolve(nil)
              end
            else
              Promise.resolve(nil)
            end
          end
        else
          Promise.resolve(nil)
        end
      end
    end

    field :security_advisory, Objects::SecurityAdvisory, description: "Fetch a Security Advisory by its GHSA ID", null: true do
      visibility :public

      argument :ghsa_id, String, "GitHub Security Advisory ID.", required: true
    end

    def security_advisory(**arguments)
      Objects::SecurityAdvisory.load_from_global_id(arguments[:ghsa_id]).then do |advisory|
        unless advisory
          raise Platform::Errors::NotFound, "Could not resolve to a Security Advisory with ID '#{arguments[:ghsa_id]}'"
        end

        advisory
      end
    end

    field :security_advisories, resolver: Resolvers::SecurityAdvisories,
                                description: "GitHub Security Advisories",
                                null: false,
                                map_to_service: :advisory_database do
                                  visibility :public
                                end

    field :security_vulnerabilities, resolver: Resolvers::SecurityVulnerabilities,
                                     description: "Software Vulnerabilities documented by GitHub Security Advisories",
                                     null: false,
                                     map_to_service: :advisory_database do
                                       visibility :public
                                     end
  end
end
