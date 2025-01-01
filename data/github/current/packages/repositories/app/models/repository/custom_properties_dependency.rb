# typed: strict
# frozen_string_literal: true

module Repository::CustomPropertiesDependency
  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(Repository))

    batch_method(:custom_properties_effective_values) do |repos|
      org_repos, non_org_repos = repos.partition { |repo| repo.owner&.organization? }

      org_repos_hash = Repositories.domain.custom_properties.repo_properties(org_repos, :effective, strip_nils: false)
      non_org_repos_hash = non_org_repos.index_with { nil }

      org_repos_hash.merge(non_org_repos_hash)
    end
  end
end
