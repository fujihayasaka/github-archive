# typed: strict
# frozen_string_literal: true

module Platform
  module Loaders
    class IssueTypeByName < Platform::Loader
      extend T::Sig

      include Issues::Domain::Provider
      include Repositories::Domain::Provider

      sig { params(repository: Repositories::IRepository, name: String).returns(Promise[T.nilable(Issues::IIssueType)]) }
      def self.load(repository, name)
        self.for.load([repository, name])
      end

      sig { params(repos_with_names: T::Array[[Repositories::IRepository, String]]).returns(T::Hash[[Repositories::IRepository, String], T.nilable(Issues::IIssueType)]) }
      def fetch(repos_with_names)
        owners = []
        # Create a mapping of repo to repo owner
        repos_with_owner = repos_with_names.map do |repo, _|
          owners << repo.owner_id
          [repo, repo.owner_id]
        end.to_h

        # Map the owner to the issue types
        owners_with_issue_types = issues_domain.issue_types.by_organizations(owners)

        repos_with_names.map do |repo_with_name|
          repo, name = repo_with_name
          # Get the issue types from the owner using the repo as the key
          repo_owner_issue_types = owners_with_issue_types[repos_with_owner[repo] || -1]
          [
            repo_with_name,
            repo_owner_issue_types&.detect do |issue_type|
              (repo.private? || !issue_type.private?) &&
                (issue_type.name&.downcase&.strip == name.downcase.strip)
            end
          ]
        end.to_h
      end
    end
  end
end
