# typed: strict
# frozen_string_literal: true

module Repository::CustomPropertiesDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  include ::CustomPropertiesCore::IPropertyTarget

  requires_ancestor { Repository }

  included do
    T.bind(self, T.class_of(Repository))

    batch_method(:custom_properties_effective_values) do |repos|
      org_repos, non_org_repos = repos.partition { |repo| repo.owner&.organization? }

      org_repos_hash = Repositories.domain.custom_properties.repo_properties(org_repos, :effective, strip_nils: false)
      non_org_repos_hash = non_org_repos.index_with { nil }

      org_repos_hash.merge(non_org_repos_hash)
    end

    sig { override.returns(T.nilable(Integer)) }
    def properties_target_id
      id
    end

    sig { override.returns(T.nilable(Integer)) }
    def properties_org_source_id
      owner&.id if owner&.organization?
    end

    sig { override.returns(T.nilable(Integer)) }
    def properties_business_source_id
      owner&.business&.id if owner&.organization?
    end
  end
end
